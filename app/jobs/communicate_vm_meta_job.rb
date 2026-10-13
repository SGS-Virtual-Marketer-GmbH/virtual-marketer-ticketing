# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

class CommunicateVmMetaJob < ApplicationJob

  retry_on Service::Ticket::Article::Type::TemporaryDeliveryError, attempts: 4, wait: lambda { |executions|
    executions * 120.seconds
  }

  def perform(article_id)
    deliver_service(article_id).execute(article_id: article_id)
  end

  private

  # Direct messages and public comments are delivered by different services.
  def deliver_service(article_id)
    type = Ticket::Article.find(article_id).type&.name

    if VmMeta::COMMENT_TYPES.include?(type)
      Service::Ticket::Article::Type::VmMetaComment::Deliver
    else
      Service::Ticket::Article::Type::VmMetaMessage::Deliver
    end
  end
end
