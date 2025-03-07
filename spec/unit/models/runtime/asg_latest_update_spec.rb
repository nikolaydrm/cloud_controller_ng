require 'spec_helper'

module VCAP::CloudController
  RSpec.describe AsgLatestUpdate, type: :model do
    describe 'Renew' do
      it 'updates asgLatestUpdate to now' do
        expect(AsgLatestUpdate.last_update).to eq Time.at(0)
        AsgLatestUpdate.renew
        expect(AsgLatestUpdate.last_update).to be > 1.minute.ago
      end

      context 'when there is no previous update' do
        it 'creates an asgLatestUpdate' do
          AsgLatestUpdate.renew
          expect(AsgLatestUpdate.last_update).to be > 1.minute.ago
        end
      end
    end

    describe 'last_update' do
      it 'returns the last update timestamp' do
        AsgLatestUpdate.const_get(:AsgTimestamp).create last_update: Time.new(2019)
        expect(AsgLatestUpdate.last_update).to eq Time.new(2019)
      end

      context 'when there is no previous update' do
        it 'returns beginng of epoch time' do
          expect(AsgLatestUpdate.last_update).to eq Time.at(0)
        end
      end
    end
  end
end
