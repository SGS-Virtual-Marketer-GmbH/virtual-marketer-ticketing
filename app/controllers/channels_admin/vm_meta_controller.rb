# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

# Provisioning API for the VmMeta (Facebook Messenger / Instagram Direct)
# channel. There is no admin UI in this version, so unlike
# ChannelsAdmin::WhatsappController this does not follow the
# asset/CanSensitiveAssets masking convention - it returns plain JSON and is
# deliberately stricter than "masked": page_access_token/app_secret/
# verify_token are never included at all, except verify_token once, in the
# create response only (the one time the caller needs it, to enter into the
# Meta App Dashboard's webhook verification field).
class ChannelsAdmin::VmMetaController < ApplicationController
  prepend_before_action :authenticate_and_authorize!

  SECRET_OPTION_KEYS = %i[page_access_token app_secret verify_token].freeze

  def area
    'VmMeta::Page'.freeze
  end

  def index
    channels = Service::Channel::Admin::List.execute(area:)

    render json: {
      channels: channels.map { |channel| channel_json(channel) },
    }
  end

  def create
    channel = Service::Channel::VmMeta::Create.execute(params: params.permit!)

    render json: channel_json(channel, reveal_verify_token: true)
  rescue => e
    raise Exceptions::UnprocessableContent, e.message
  end

  def update
    channel = Service::Channel::VmMeta::Update.execute(params: params.permit!, channel_id: params[:id])

    render json: channel_json(channel)
  rescue => e
    raise Exceptions::UnprocessableContent, e.message
  end

  private

  def channel_json(channel, reveal_verify_token: false)
    options = channel.options.to_h.symbolize_keys.except(*SECRET_OPTION_KEYS)
    options[:verify_token] = channel.options[:verify_token] if reveal_verify_token

    {
      id:           channel.id,
      area:         channel.area,
      group_id:     channel.group_id,
      active:       channel.active,
      options:      options,
      callback_url: callback_url(channel),
    }
  end

  def callback_url(channel)
    # Rails.configuration.api_path already starts with a leading slash
    # (e.g. '/api/v1', see config/application.rb) - do not add another one
    # here, or this produces a double slash ('https://host//api/v1/...').
    "#{Setting.get('http_type')}://#{Setting.get('fqdn')}#{Rails.configuration.api_path}/channels_vm_meta_webhook/#{channel.options[:callback_url_uuid]}"
  end
end
