require 'spec_helper'

## NOTICE: Prefer request specs over controller specs as per ADR #0003 ##

module VCAP::CloudController
  RSpec.describe AppBitsUploadController do
    let(:app_event_repository) { Repositories::AppEventRepository.new }

    before { CloudController::DependencyLocator.instance.register(:app_event_repository, app_event_repository) }

    describe 'PUT /v2/app/:id/bits' do
      before do
        TestConfig.override(
          **config_override.merge(
            directories: { tmpdir: File.dirname(valid_zip.path) },
            kubernetes: {}
          )
        )
      end

      let(:tmpdir) { Dir.mktmpdir }
      after { FileUtils.rm_rf(tmpdir) }

      let(:valid_zip) do
        zip_name = File.join(tmpdir, 'file.zip')
        TestZip.create(zip_name, 1, 1024)
        zip_file = File.new(zip_name)
        Rack::Test::UploadedFile.new(zip_file)
      end

      let(:config_override) { {} }
      let(:headers) { headers_for(user) }
      let(:process) { ProcessModel.make }

      def make_request
        put "/v2/apps/#{process.app.guid}/bits", req_body, form_headers(headers)
      end

      context 'as an admin' do
        let(:headers) { admin_headers }
        let(:req_body) { { resources: '[]', application: valid_zip } }

        it 'allows upload even if app_bits_upload flag is disabled' do
          FeatureFlag.make(name: 'app_bits_upload', enabled: false)
          make_request
          expect(last_response.status).to eq(201)
        end
      end

      context 'as a developer' do
        let(:user) { make_developer_for_space(process.space) }

        context 'when the app_bits_upload feature flag is disabled' do
          let(:req_body) { { resources: '[]', application: valid_zip } }

          before do
            FeatureFlag.make(name: 'app_bits_upload', enabled: false, error_message: nil)
            make_request
            process.refresh
          end

          it 'returns FeatureDisabled and does not upload' do
            expect(last_response.status).to eq(403)
            expect(decoded_response['error_code']).to match(/FeatureDisabled/)
            expect(decoded_response['description']).to match(/app_bits_upload/)

            expect(process.package_hash).to be_nil
          end

          it 'does not modify the package state' do
            expect(process.package_state).not_to eq 'FAILED'
          end
        end

        context 'when the app_bits_upload feature flag is enabled' do
          before do
            FeatureFlag.make(name: 'app_bits_upload', enabled: true)
          end

          context 'with an empty request' do
            let(:req_body) { {} }

            before do
              # rack_test overrides 'CONTENT_TYPE' header with 'boundary' which causes errors when the request does not contain an application
              headers[:multipart] = false
            end

            it 'fails to upload' do
              make_request

              expect(last_response.status).to eq(400)
              expect(JSON.parse(last_response.body)['description']).to include('missing :resources')

              process.refresh
              expect(process.package_hash).to be_nil
              expect(process.package_state).to eq 'FAILED'
            end
          end

          context 'with empty resources and no application' do
            let(:req_body) { { resources: '[]' } }

            before do
              # rack_test overrides 'CONTENT_TYPE' header with 'boundary' which causes errors when the request does not contain an application
              headers[:multipart] = false
            end

            it 'fails to upload' do
              make_request

              expect(last_response.status).to eq(400)
              expect(JSON.parse(last_response.body)['description']).to include('Invalid zip')

              process.refresh
              expect(process.package_hash).to be_nil
              expect(process.package_state).to eq 'FAILED'
            end
          end

          context 'with at least one resource and no application' do
            let(:req_body) { { resources: JSON.dump([{ 'fn' => 'lol', 'sha1' => 'abc', 'size' => 2048 }]) } }

            before do
              # rack_test overrides 'CONTENT_TYPE' header with 'boundary' which causes errors when the request does not contain an application
              headers[:multipart] = false
            end

            it 'succeeds to upload' do
              make_request
              expect(last_response.status).to eq(201)
              expect(process.refresh.package_hash).not_to be_nil
            end
          end

          context 'with at least one resource and an application' do
            let(:req_body) { { resources: JSON.dump([{ 'fn' => 'lol', 'sha1' => 'abc', 'size' => 2048 }]), application: valid_zip } }

            it 'succeeds to upload' do
              make_request
              expect(last_response.status).to eq(201)
              expect(process.refresh.package_hash).not_to be_nil
            end
          end

          context 'with no resources and application' do
            let(:req_body) { { application: valid_zip } }

            it 'fails to upload' do
              make_request

              expect(last_response.status).to eq(400)
              expect(JSON.parse(last_response.body)['description']).to include('missing :resources')

              process.refresh
              expect(process.package_hash).to be_nil
              expect(process.package_state).to eq 'FAILED'
            end
          end

          context 'with empty resources' do
            let(:req_body) do
              { resources: '[]', application: valid_zip }
            end

            it 'succeeds to upload' do
              make_request
              expect(last_response.status).to eq(201)
              expect(process.refresh.package_hash).not_to be_nil
            end
          end

          context 'with invalid resources' do
            let(:req_body) do
              { resources: '[abcddf]', application: valid_zip }
            end

            it 'fails to upload' do
              make_request

              expect(last_response.status).to eq(400)
              expect(decoded_response['error_code']).to match(/AppBitsUploadInvalid/)
            end
          end

          context 'with a bad zip file' do
            let(:bad_zip) { Rack::Test::UploadedFile.new(Tempfile.new('bad_zip')) }
            let(:req_body) do
              { resources: '[]', application: bad_zip }
            end

            it 'fails to upload' do
              make_request

              expect(last_response.status).to eq(400)
              expect(JSON.parse(last_response.body)['description']).to include('Invalid zip')

              process.refresh
              expect(process.package_hash).to be_nil
              expect(process.package_state).to eq 'FAILED'
            end
          end

          context 'with a valid zip file' do
            let(:req_body) do
              { resources: '[]', application: valid_zip }
            end

            it 'succeeds to upload' do
              make_request
              expect(last_response.status).to eq(201)
              expect(process.refresh.package_hash).not_to be_nil
            end

            it 'records audit events' do
              expect { make_request }.to change(Event, :count).by(1)
              event = Event.find(type: 'audit.app.upload-bits')
              expect(event.actee).to eq(process.app.guid)
            end

            context 'when the upload will finish after the auth token expires' do
              let(:config_override) do
                { app_bits_upload_grace_period_in_seconds: 200 }
              end

              context 'but the upload will finish inside the grace period' do
                it 'succeeds' do
                  headers = headers_for(user)

                  Timecop.travel(Time.now.utc + 1.week + 100.seconds) do
                    put "/v2/apps/#{process.app.guid}/bits", req_body, headers
                  end
                  expect(last_response.status).to eq(201)
                end
              end

              context 'and the upload will finish after the grace period' do
                it 'fails to authorize the upload' do
                  headers = headers_for(user)

                  Timecop.travel(Time.now.utc + 1.week + 10_000.seconds) do
                    put "/v2/apps/#{process.app.guid}/bits", req_body, headers
                  end
                  expect(last_response.status).to eq(401)
                end
              end
            end
          end

          describe 'resources' do
            context 'with a bad file path' do
              let(:req_body) { { resources: JSON.dump([{ 'fn' => '../../lol', 'sha1' => 'abc', 'size' => 2048 }]), application: valid_zip } }

              it 'fails to upload' do
                make_request

                expect(last_response.status).to eq(400)
                expect(JSON.parse(last_response.body)['description']).to include("'../../lol' is not safe")

                process.refresh
                expect(process.package_hash).to be_nil
                expect(process.package_state).to eq 'FAILED'
              end
            end

            context 'with a bad file mode' do
              context 'when the file is not readable by owner' do
                let(:req_body) { { resources: JSON.dump([{ 'fn' => 'lol', 'sha1' => 'abc', 'size' => 2048, 'mode' => '377' }]), application: valid_zip } }

                it 'fails to upload' do
                  make_request
                  expect(last_response.status).to eq(400)
                  expect(JSON.parse(last_response.body)['description']).to include("'377' with path 'lol' is invalid")

                  process.refresh
                  expect(process.package_hash).to be_nil
                  expect(process.package_state).to eq 'FAILED'
                end
              end

              context 'when the file is not writable by owner' do
                let(:req_body) { { resources: JSON.dump([{ 'fn' => 'lol', 'sha1' => 'abc', 'size' => 2048, 'mode' => '577' }]), application: valid_zip } }

                it 'fails to upload' do
                  make_request
                  expect(last_response.status).to eq(400)
                  expect(JSON.parse(last_response.body)['description']).to include("'577' with path 'lol' is invalid")

                  process.refresh
                  expect(process.package_hash).to be_nil
                  expect(process.package_state).to eq 'FAILED'
                end
              end
            end
          end
        end
      end

      context 'as a non-developer' do
        let(:user) { make_user_for_space(process.space) }
        let(:req_body) do
          { resources: '[]', application: valid_zip }
        end

        it 'returns 403' do
          make_request
          expect(last_response.status).to eq(403)
        end
      end

      context 'when running async=true' do
        let(:user) { make_developer_for_space(process.space) }
        let(:req_body) do
          { resources: '[]', application: valid_zip }
        end
        let(:config_override) do
          { index: 99, name: 'api_z1' }
        end

        it 'creates a delayed job' do
          expect do
            put "/v2/apps/#{process.app.guid}/bits?async=true", req_body, headers_for(user)
          end.to change(Delayed::Job, :count).by(1)

          response_body = JSON.parse(last_response.body, symbolize_names: true)
          job = Delayed::Job.last
          expect(job.handler).to include(process.reload.latest_package.guid)
          expect(job.queue).to eq('cc-api_z1-99')
          expect(job.guid).not_to be_nil
          expect(last_response.status).to eq 201
          expect(response_body).to eq({
                                        metadata: {
                                          guid: job.guid,
                                          created_at: job.created_at.iso8601,
                                          url: "/v2/jobs/#{job.guid}"
                                        },
                                        entity: {
                                          guid: job.guid,
                                          status: 'queued'
                                        }
                                      })
        end

        describe 'resources' do
          context 'with a bad file path' do
            let(:req_body) { { resources: JSON.dump([{ 'fn' => '../../lol', 'sha1' => 'abc', 'size' => 2048 }]), application: valid_zip } }

            it 'fails to upload' do
              expect do
                put "/v2/apps/#{process.app.guid}/bits?async=true", req_body, form_headers(headers_for(user))
              end.to change(Delayed::Job, :count).by(1)

              execute_all_jobs(expected_successes: 0, expected_failures: 1)

              process.refresh
              expect(process.package_hash).to be_nil
              expect(process.package_state).to eq 'FAILED'
            end
          end

          context 'with a bad file mode' do
            context 'when the file is not readable by owner' do
              let(:req_body) { { resources: JSON.dump([{ 'fn' => 'lol', 'sha1' => 'abc', 'size' => 2048, 'mode' => '300' }]), application: valid_zip } }

              before do
                FeatureFlag.make(name: 'app_bits_upload', enabled: true)
              end

              it 'fails to upload' do
                expect do
                  put "/v2/apps/#{process.app.guid}/bits?async=true", req_body, form_headers(headers_for(user))
                end.to change(Delayed::Job, :count).by(1)

                execute_all_jobs(expected_successes: 0, expected_failures: 1)

                process.refresh
                expect(process.package_hash).to be_nil
                expect(process.package_state).to eq 'FAILED'
              end
            end

            context 'when the file is not writable by owner' do
              let(:req_body) { { resources: JSON.dump([{ 'fn' => 'lol', 'sha1' => 'abc', 'size' => 2048, 'mode' => '577' }]), application: valid_zip } }

              it 'fails to upload' do
                expect do
                  put "/v2/apps/#{process.app.guid}/bits?async=true", req_body, form_headers(headers_for(user))
                end.to change(Delayed::Job, :count).by(1)

                execute_all_jobs(expected_successes: 0, expected_failures: 1)

                process.refresh
                expect(process.package_hash).to be_nil
                expect(process.package_state).to eq 'FAILED'
              end
            end
          end
        end
      end

      context 'when the app is a docker app' do
        let(:process) { ProcessModel.make(app: AppModel.make(:docker)) }
        let(:req_body) { { resources: '[]', application: valid_zip } }
        let(:headers) { admin_headers }

        it 'raises an error' do
          make_request

          expect(last_response.status).to eq(422)
          expect(decoded_response['error_code']).to match(/UnprocessableEntity/)
          expect(decoded_response['description']).to match(/cannot upload bits to a docker app/)
        end
      end
    end

    describe 'POST /v2/apps/:guid/copy_bits' do
      let(:dest_process) { ProcessModel.make }
      let(:src_process) { ProcessModelFactory.make }
      let(:json_payload) { { 'source_app_guid' => src_process.app.guid }.to_json }

      class FakeCopier
        def initialize(src_process, dest_process, app_event_repo, user, email)
          @src_process = src_process
          @dest_process = dest_process
          @app_event_repo = app_event_repo
          @user = user
          @email = email
        end

        def perform
          FakeCopier.copies << [@src_process, @dest_process, @app_event_repo, @user, @email]
        end

        class << self
          attr_accessor :copies
        end
        self.copies = []
      end

      context 'when no source guid is sent' do
        let(:json_payload) { '{}' }

        it 'fails to copy application bits' do
          post "/v2/apps/#{dest_process.app.guid}/copy_bits", json_payload, admin_headers

          expect(last_response.status).to eq(400)

          expect(decoded_response['error_code']).to match(/AppBitsCopyInvalid/)
          expect(decoded_response['description']).to match(/missing source_app_guid/)
        end
      end

      context 'when a source guid is supplied' do
        it 'returns a delayed job' do
          expect do
            post "/v2/apps/#{dest_process.app.guid}/copy_bits", json_payload, admin_headers
          end.to change(Delayed::Job, :count).by(1)

          job = Delayed::Job.last
          expected_response = {
            'metadata' => {
              'guid' => job.guid,
              'created_at' => job.created_at.iso8601,
              'url' => "/v2/jobs/#{job.guid}"
            },
            'entity' => {
              'guid' => job.guid,
              'status' => 'queued'
            }
          }

          expect(job.queue).to eq(Jobs::Queues.generic)
          expect(last_response.status).to eq(201)
          expect(decoded_response).to eq(expected_response)
        end

        it 'records audit events on the source and destination apps' do
          expect do
            post "/v2/apps/#{dest_process.app.guid}/copy_bits", json_payload, admin_headers
          end.to change(Event, :count).by(2)

          source_event = Event.find(actee: src_process.app.guid)
          dest_event = Event.find(actee: dest_process.app.guid)

          expect(source_event.type).to eq('audit.app.copy-bits')
          expect(dest_event.type).to eq('audit.app.copy-bits')
        end

        context 'validation permissions' do
          it 'allows an admin' do
            stub_const('VCAP::CloudController::Jobs::Runtime::AppBitsCopier', FakeCopier)
            post "/v2/apps/#{dest_process.app.guid}/copy_bits", json_payload, admin_headers

            expect(last_response.status).to eq(201)
          end

          it 'disallows when not a developer of destination space' do
            stub_const('VCAP::CloudController::Jobs::Runtime::AppBitsCopier', FakeCopier)
            user = make_developer_for_space(src_process.space)

            post "/v2/apps/#{dest_process.app.guid}/copy_bits", json_payload, headers_for(user)

            expect(last_response.status).to eq(403)
          end

          it 'disallows when not a developer of source space' do
            stub_const('VCAP::CloudController::Jobs::Runtime::AppBitsCopier', FakeCopier)
            user = make_developer_for_space(dest_process.space)

            post "/v2/apps/#{dest_process.app.guid}/copy_bits", json_payload, headers_for(user)

            expect(last_response.status).to eq(403)
          end

          it 'allows when a developer of both spaces' do
            stub_const('VCAP::CloudController::Jobs::Runtime::AppBitsCopier', FakeCopier)
            user = make_developer_for_space(dest_process.space)
            src_process.organization.add_user(user)
            src_process.space.add_developer(user)

            post "/v2/apps/#{dest_process.app.guid}/copy_bits", json_payload, headers_for(user)
            expect(last_response.status).to eq(201)
          end
        end
      end
    end
  end
end
