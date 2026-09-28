# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

class CommunicateVmMetaJob < ApplicationJob

  retry_on Service::Ticket::Article::Type::TemporaryDeliveryError, attempts: 4, wait: lambda { |executions|
    executions * 120.seconds
  }

  def perform(article_id)
    Service::Ticket::Article::Type::VmMetaMessage::Deliver.execute(article_id: article_id)
  end
end
