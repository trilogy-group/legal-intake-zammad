# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

RSpec.describe Service::AI::Analytics::GenerateReport::WithUsages do
  describe '#execute' do
    let(:ai_analytics_run) { create(:ai_analytics_run) }

    before { ai_analytics_run }

    context 'when format is xlsx' do
      it 'returns the report as XLSX' do
        expect(described_class.new(format: :xlsx).execute)
          .to be_a(String)
      end
    end

    context 'when format is json' do
      it 'returns the report as JSON' do
        response = described_class.new(format: :json).execute
        expect(JSON.parse(response))
          .to contain_exactly(include('id' => ai_analytics_run.id))
      end
    end
  end

  describe '#parsed_records' do
    context 'when no records exist' do
      it 'returns an empty array' do
        expect(described_class.new.send(:parsed_records)).to be_empty
      end
    end

    context 'when a record exists without usages' do
      let(:ai_analytics_run) { create(:ai_analytics_run) }

      before { ai_analytics_run }

      it 'returns the parsed record' do
        expect(described_class.new.send(:parsed_records))
          .to contain_exactly(
            include(
              id:             ai_analytics_run.id,
              usages_count:   0,
              likes_count:    0,
              dislikes_count: 0,
              comments:       []
            )
          )
      end

      context 'when a record with an error exists' do
        it 'does not include that record' do
          create(:ai_analytics_run, :with_error)

          expect(described_class.new.send(:parsed_records))
            .to contain_exactly(
              include(
                id: ai_analytics_run.id,
              )
            )
        end
      end
    end

    context 'when a record exists with some usages' do
      let(:user)                 { create(:agent) }
      let(:user_2)               { create(:agent) }
      let(:ai_analytics_run)     { create(:ai_analytics_run) }
      let(:ai_analytics_usage)   { create(:ai_analytics_usage, rating: true, ai_analytics_run:, user:) }
      let(:ai_analytics_usage_2) { create(:ai_analytics_usage, rating: false, comment: 'some comment here', ai_analytics_run:, user: user_2) }
      let(:ai_analytics_run_2)   { create(:ai_analytics_run) }
      let(:ai_analytics_usage_3) { create(:ai_analytics_usage, ai_analytics_run: ai_analytics_run_2, user:) }
      let(:ai_analytics_run_3)   { create(:ai_analytics_run) }

      before do
        ai_analytics_usage
        ai_analytics_usage_2
        ai_analytics_usage_3
        ai_analytics_run_3
      end

      it 'returns the parsed record' do
        expect(described_class.new.send(:parsed_records))
          .to contain_exactly(
            include(
              id:             ai_analytics_run.id,
              usages_count:   2,
              likes_count:    1,
              dislikes_count: 1,
              comments:       [{
                user_id:    user_2.id,
                comment:    'some comment here',
                created_at: ai_analytics_usage_2.created_at,
                rating:     false,
                user_login: user_2.login
              }]
            ),
            include(
              id:             ai_analytics_run_2.id,
              usages_count:   1,
              likes_count:    0,
              dislikes_count: 0,
              comments:       []
            ),
            include(
              id:             ai_analytics_run_3.id,
              usages_count:   0,
              likes_count:    0,
              dislikes_count: 0,
              comments:       []
            )
          )
      end
    end

    context 'when a scope is given' do
      let(:ticket) { create(:ticket) }
      let(:ai_analytics_run)   { create(:ai_analytics_run, related_object: ticket) }
      let(:ai_analytics_run_2) { create(:ai_analytics_run) }

      before do
        ai_analytics_run
        ai_analytics_run_2
      end

      it 'returns records within the scope' do
        scope = AI::Analytics::Run.where(related_object: ticket)

        expect(described_class.new(scope:).send(:parsed_records))
          .to contain_exactly(
            include(
              id: ai_analytics_run.id,
            )
          )
      end
    end

    context 'when multiple records exist' do
      let(:ai_analytics_run_1) { create(:ai_analytics_run) }
      let(:ai_analytics_run_2) { create(:ai_analytics_run) }
      let(:ai_analytics_run_3) { create(:ai_analytics_run) }

      before do
        ai_analytics_run_1
        ai_analytics_run_2
        ai_analytics_run_3
      end

      it 'returns records ordered by id descending (newest first)' do
        parsed_records = described_class.new.send(:parsed_records)
        record_ids = parsed_records.map { |record| record[:id] }

        expect(record_ids).to eq([ai_analytics_run_3.id, ai_analytics_run_2.id, ai_analytics_run_1.id])
      end
    end

    context 'when records span multiple batches' do
      before do
        # Use small batch size to test batching with few records
        stub_const('Service::AI::Analytics::GenerateReport::Base::BATCH_SIZE', 2)
      end

      let!(:ai_analytics_runs) { create_list(:ai_analytics_run, 5) }

      it 'returns all records ordered by id descending across batch boundaries' do
        parsed_records = described_class.new.send(:parsed_records)
        record_ids = parsed_records.map { |record| record[:id] }

        # With BATCH_SIZE=2, records are processed in batches: [5,4], [3,2], [1]
        # All should be returned in descending order: 5, 4, 3, 2, 1
        expected_ids = ai_analytics_runs.map(&:id).sort.reverse
        expect(record_ids).to eq(expected_ids)
      end

      it 'respects the result limit when records exceed it' do
        # Create one more record to exceed the result limit
        extra_run = create(:ai_analytics_run)

        # With BATCH_SIZE=2 and RESULT_SIZE=4, we take 2 batches (4 records max)
        stub_const('Service::AI::Analytics::GenerateReport::Base::RESULT_SIZE', 4)

        parsed_records = described_class.new.send(:parsed_records)
        record_ids = parsed_records.map { |record| record[:id] }

        # Should return only the 4 newest records (highest IDs) in descending order
        all_ids = AI::Analytics::Run.order(id: :desc).limit(4).pluck(:id)
        expect(record_ids).to eq(all_ids)
        expect(record_ids).to include(extra_run.id)
        expect(record_ids.length).to eq(4)
      end
    end
  end
end
