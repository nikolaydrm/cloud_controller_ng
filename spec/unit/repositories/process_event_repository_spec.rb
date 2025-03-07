require 'spec_helper'
require 'repositories/process_event_repository'

module VCAP::CloudController
  module Repositories
    RSpec.describe ProcessEventRepository do
      let(:app) { AppModel.make(name: 'zach-loves-kittens') }
      let(:process) { ProcessModel.make(app: app, type: 'potato') }
      let(:user_guid) { 'user_guid' }
      let(:email) { 'user-email' }
      let(:user_name) { 'user-name' }
      let(:user_audit_info) { UserAuditInfo.new(user_guid: user_guid, user_name: user_name, user_email: email) }

      describe '.record_create' do
        it 'creates a new audit.app.start event' do
          event = ProcessEventRepository.record_create(process, user_audit_info)
          event.reload

          expect(event.type).to eq('audit.app.process.create')
          expect(event.actor).to eq(user_guid)
          expect(event.actor_type).to eq('user')
          expect(event.actor_name).to eq(email)
          expect(event.actor_username).to eq(user_name)
          expect(event.actee).to eq(app.guid)
          expect(event.actee_type).to eq('app')
          expect(event.actee_name).to eq('zach-loves-kittens')
          expect(event.space_guid).to eq(app.space.guid)
          expect(event.organization_guid).to eq(app.space.organization.guid)

          expect(event.metadata).to eq({
                                         'process_guid' => process.guid,
                                         'process_type' => 'potato'
                                       })
        end

        context 'event is manifest triggered' do
          it 'includes manifest_triggered: true in the metadata' do
            event = ProcessEventRepository.record_create(process, user_audit_info, manifest_triggered: true)
            event.reload

            expect(event.type).to eq('audit.app.process.create')
            expect(event.actor).to eq(user_guid)
            expect(event.actor_type).to eq('user')
            expect(event.actor_name).to eq(email)
            expect(event.actor_username).to eq(user_name)
            expect(event.actee).to eq(app.guid)
            expect(event.actee_type).to eq('app')
            expect(event.actee_name).to eq('zach-loves-kittens')
            expect(event.space_guid).to eq(app.space.guid)
            expect(event.organization_guid).to eq(app.space.organization.guid)

            expect(event.metadata).to eq({
                                           'process_guid' => process.guid,
                                           'process_type' => 'potato',
                                           'manifest_triggered' => true
                                         })
          end
        end
      end

      describe '.record_delete' do
        it 'creates a new audit.app.delete event' do
          event = ProcessEventRepository.record_delete(process, user_audit_info)
          event.reload

          expect(event.type).to eq('audit.app.process.delete')
          expect(event.actor).to eq(user_guid)
          expect(event.actor_type).to eq('user')
          expect(event.actor_username).to eq(user_name)
          expect(event.actor_name).to eq(email)
          expect(event.actee).to eq(app.guid)
          expect(event.actee_type).to eq('app')
          expect(event.actee_name).to eq('zach-loves-kittens')
          expect(event.space_guid).to eq(app.space.guid)
          expect(event.organization_guid).to eq(app.space.organization.guid)

          expect(event.metadata).to eq({
                                         'process_guid' => process.guid,
                                         'process_type' => 'potato'
                                       })
        end
      end

      describe '.record_scale' do
        it 'creates a new audit.app.delete event' do
          request = { instances: 10, memory_in_mb: 512, disk_in_mb: 2048 }
          event = ProcessEventRepository.record_scale(process, user_audit_info, request)
          event.reload

          expect(event.type).to eq('audit.app.process.scale')
          expect(event.actor).to eq(user_guid)
          expect(event.actor_type).to eq('user')
          expect(event.actor_name).to eq(email)
          expect(event.actor_username).to eq(user_name)
          expect(event.actee).to eq(app.guid)
          expect(event.actee_type).to eq('app')
          expect(event.actee_name).to eq('zach-loves-kittens')
          expect(event.space_guid).to eq(app.space.guid)
          expect(event.organization_guid).to eq(app.space.organization.guid)

          expect(event.metadata).to eq({
                                         'process_guid' => process.guid,
                                         'process_type' => 'potato',
                                         'request' => {
                                           'instances' => 10,
                                           'memory_in_mb' => 512,
                                           'disk_in_mb' => 2048
                                         }
                                       })
        end

        context 'when the scale event is manifest triggered' do
          it 'includes manifest_triggered: true in the metadata' do
            request = { instances: 10, memory_in_mb: 512, disk_in_mb: 2048 }
            event = ProcessEventRepository.record_scale(process, user_audit_info, request, manifest_triggered: true)

            expect(event.metadata).to eq({
                                           process_guid: process.guid,
                                           process_type: 'potato',
                                           request: {
                                             instances: 10,
                                             memory_in_mb: 512,
                                             disk_in_mb: 2048
                                           },
                                           manifest_triggered: true
                                         })
          end
        end
      end

      describe '.record_update' do
        it 'creates a new audit.app.update event' do
          event = ProcessEventRepository.record_update(process, user_audit_info, { anything: 'whatever' })
          event.reload

          expect(event.type).to eq('audit.app.process.update')
          expect(event.actor).to eq(user_guid)
          expect(event.actor_type).to eq('user')
          expect(event.actor_name).to eq(email)
          expect(event.actor_username).to eq(user_name)
          expect(event.actee).to eq(app.guid)
          expect(event.actee_type).to eq('app')
          expect(event.actee_name).to eq('zach-loves-kittens')
          expect(event.space_guid).to eq(app.space.guid)
          expect(event.organization_guid).to eq(app.space.organization.guid)

          expect(event.metadata).to eq({
                                         'process_guid' => process.guid,
                                         'process_type' => 'potato',
                                         'request' => {
                                           'anything' => 'whatever'
                                         }
                                       })
        end

        it 'redacts metadata.request.command' do
          event = ProcessEventRepository.record_update(process, user_audit_info, { command: 'censor this' })
          event.reload

          expect(event.metadata).to match(hash_including(
                                            'request' => {
                                              'command' => '[PRIVATE DATA HIDDEN]'
                                            }
                                          ))
        end

        context 'when the update event is manifest triggered' do
          it 'includes manifest_triggered: true in the metadata' do
            event = ProcessEventRepository.record_update(process, user_audit_info, { anything: 'whatever' }, manifest_triggered: true)
            event.reload

            expect(event.type).to eq('audit.app.process.update')
            expect(event.actor).to eq(user_guid)
            expect(event.actor_type).to eq('user')
            expect(event.actor_name).to eq(email)
            expect(event.actor_username).to eq(user_name)
            expect(event.actee).to eq(app.guid)
            expect(event.actee_type).to eq('app')
            expect(event.actee_name).to eq('zach-loves-kittens')
            expect(event.space_guid).to eq(app.space.guid)
            expect(event.organization_guid).to eq(app.space.organization.guid)

            expect(event.metadata).to eq({
                                           'process_guid' => process.guid,
                                           'process_type' => 'potato',
                                           'manifest_triggered' => true,
                                           'request' => {
                                             'anything' => 'whatever'
                                           }
                                         })
          end
        end
      end

      describe '.record_terminate' do
        it 'creates a new audit.app.terminate_instance event' do
          index = 0
          event = ProcessEventRepository.record_terminate(process, user_audit_info, index)
          event.reload

          expect(event.type).to eq('audit.app.process.terminate_instance')
          expect(event.actor).to eq(user_guid)
          expect(event.actor_type).to eq('user')
          expect(event.actor_name).to eq(email)
          expect(event.actor_username).to eq(user_name)
          expect(event.actee).to eq(app.guid)
          expect(event.actee_type).to eq('app')
          expect(event.actee_name).to eq('zach-loves-kittens')
          expect(event.space_guid).to eq(app.space.guid)
          expect(event.organization_guid).to eq(app.space.organization.guid)

          expect(event.metadata).to eq({
                                         'process_guid' => process.guid,
                                         'process_type' => 'potato',
                                         'process_index' => 0
                                       })
        end
      end

      describe '.record_crash' do
        let(:exit_description) { 'X' * AppEventRepository::TRUNCATE_THRESHOLD * 2 }
        let(:crash_payload) do
          {
            'instance' => 'abc',
            'index' => 3,
            'cell_id' => 'some-cell',
            'exit_status' => 137,
            'exit_description' => exit_description,
            'reason' => 'CRASHED'
          }
        end

        it 'creates a new audit.app.crash event' do
          event = ProcessEventRepository.record_crash(process, crash_payload)
          event.reload

          expect(event.type).to eq('audit.app.process.crash')
          expect(event.actor).to eq(process.guid)
          expect(event.actor_type).to eq('process')
          expect(event.actor_name).to eq('potato')
          expect(event.actor_username).to eq('')
          expect(event.actee).to eq(app.guid)
          expect(event.actee_type).to eq('app')
          expect(event.actee_name).to eq('zach-loves-kittens')
          expect(event.space_guid).to eq(app.space.guid)
          expect(event.organization_guid).to eq(app.space.organization.guid)

          expect(event.metadata['instance']).to eq('abc')
          expect(event.metadata['index']).to eq(3)
          expect(event.metadata['cell_id']).to eq('some-cell')
          expect(event.metadata['exit_status']).to eq(137)
          expect(event.metadata['exit_description'].length).to eq(AppEventRepository::TRUNCATE_THRESHOLD)
          expect(event.metadata['exit_description']).to eq(exit_description.truncate(AppEventRepository::TRUNCATE_THRESHOLD, omission: ' (truncated)'))
          expect(event.metadata['reason']).to eq('CRASHED')
        end
      end

      describe '.record_rescheduling' do
        let(:rescheduling_payload) do
          {
            'instance' => Sham.guid,
            'index' => 3,
            'cell_id' => 'some-cell',
            'reason' => 'Helpful reason for rescheduling'
          }
        end

        it 'creates a new audit.app.process.rescheduling event' do
          event = ProcessEventRepository.record_rescheduling(process, rescheduling_payload)
          event.reload

          expect(event.type).to eq('audit.app.process.rescheduling')
          expect(event.actor).to eq(process.guid)
          expect(event.actor_type).to eq('process')
          expect(event.actor_name).to eq('potato')
          expect(event.actor_username).to eq('')
          expect(event.actee).to eq(app.guid)
          expect(event.actee_type).to eq('app')
          expect(event.actee_name).to eq('zach-loves-kittens')
          expect(event.space_guid).to eq(app.space.guid)
          expect(event.organization_guid).to eq(app.space.organization.guid)

          expect(event.metadata).to eq(rescheduling_payload)
        end
      end
    end
  end
end
