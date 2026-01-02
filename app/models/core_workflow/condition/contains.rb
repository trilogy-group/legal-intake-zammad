# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

class CoreWorkflow::Condition::Contains < CoreWorkflow::Condition::Backend
  def match
    (value & condition_value).count.positive?
  end
end
