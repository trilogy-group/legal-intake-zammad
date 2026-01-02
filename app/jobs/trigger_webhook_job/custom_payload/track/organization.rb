# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

class TriggerWebhookJob::CustomPayload::Track::Organization < TriggerWebhookJob::CustomPayload::Track
  def self.klass
    'Organization'
  end
end
