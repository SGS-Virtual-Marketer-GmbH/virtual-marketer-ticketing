# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

class ChannelsVmMetaController < ApplicationController
  skip_before_action :verify_csrf_token, only: %i[verify_webhook perform_webhook]

  def verify_webhook
    configuration = VmMeta::Webhook::Configuration.new(options: params)
    challenge = configuration.verify!

    render plain: challenge, status: :ok
  rescue VmMeta::Webhook::Configuration::VerificationError, VmMeta::Webhook::NoChannelError => e
    Rails.logger.error e.message
    log_request

    render plain: 'Forbidden', status: :forbidden
  end

  def perform_webhook
    signature = request.headers['X-Hub-Signature-256'].to_s.sub('sha256=', '')
    uuid      = params[:callback_url_uuid]
    json      = request.raw_post

    payload = VmMeta::Webhook::Payload.new(json:, uuid:, signature:)
    payload.process

    render json: {}, status: :ok
  rescue VmMeta::Webhook::Payload::SignatureError => e
    Rails.logger.error e.message
    log_request

    render json: {}, status: :unauthorized
  rescue VmMeta::Webhook::NoChannelError, VmMeta::Webhook::Payload::ProcessableError => e
    # Fail with a 200 for anything past signature validation, the same way
    # the WhatsApp webhook does - any other status code would make Meta
    # retry the request, which is not what we want for e.g. an unsupported
    # message type or a channel that was since deactivated.
    Rails.logger.error(e.respond_to?(:reason) && e.reason.present? ? "#{e.message}: #{e.reason}" : e.message)
    log_request

    render json: {}, status: :ok
  end

  private

  # Unauthenticated callers can reach every failure path here, so the log line
  # carries only what is needed to tell what happened: no headers (signature,
  # cookies, proxy data) and no body (customer text). Meta's own dashboard shows
  # the payload of a failed delivery if it is ever needed.
  def log_request
    Rails.logger.error "VmMeta Webhook: #{request.method} channel=#{params[:callback_url_uuid].to_s.first(36)} bytes=#{request.raw_post.to_s.bytesize} signature=#{request.headers['X-Hub-Signature-256'].present? ? 'present' : 'missing'}"
  end
end
