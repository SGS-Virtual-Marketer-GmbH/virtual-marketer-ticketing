# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

# Approved WhatsApp message templates for a Business Account, normalized into
# the shape the "send a template" UI and Whatsapp::Outgoing::Message::Template
# need -- so nothing else in the app has to know Meta's own template JSON
# layout (an array of HEADER/BODY/FOOTER/BUTTONS components, each shaped
# differently).
#
# Only APPROVED templates are returned -- a PENDING or REJECTED template
# cannot be sent, and offering it would just produce a Meta error at send
# time instead of here where we can explain why.
class Whatsapp::Account::Templates < Whatsapp::Client

  attr_reader :templates_api, :business_id

  PAGE_SIZE = 250

  UNSUPPORTED_HEADER_FORMATS = %w[IMAGE VIDEO DOCUMENT LOCATION].freeze

  PLACEHOLDER_PATTERN = /\{\{\s*([a-zA-Z0-9_]+)\s*\}\}/

  def initialize(access_token:, business_id:)
    super(access_token:)

    raise ArgumentError, __("The required parameter 'business_id' is missing.") if business_id.nil?

    @business_id   = business_id
    @templates_api = WhatsappSdk::Api::Templates.new client
  end

  def all
    fetch_all
      .select { |template| component_field(template, :status).to_s.upcase == 'APPROVED' }
      .map { |template| normalize(template) }
  rescue WhatsappSdk::Api::Responses::HttpResponseError => e
    # handle_error raises when Meta sent an error body; without one it returns
    # nil, and a nil here would be cached as "no templates".
    handle_error(response: e)
    raise CloudAPIError.new(e.message, e)
  end

  private

  # `WhatsappSdk::Api::Templates#list(business_id:, limit:)` in whatsapp_sdk
  # 1.1.0 takes no paging cursor (checked against the installed gem), so one
  # page is all there is. PAGE_SIZE is far above what a real account holds.
  def fetch_all
    page = templates_api.list(business_id: business_id.to_i, limit: PAGE_SIZE)
    Array(page&.records)
  end

  def normalize(template)
    components = Array(component_field(template, :components_json))
    header     = components.find { |c| component_type(c) == 'HEADER' }
    body       = components.find { |c| component_type(c) == 'BODY' }
    footer     = components.find { |c| component_type(c) == 'FOOTER' }
    buttons    = components.find { |c| component_type(c) == 'BUTTONS' }

    header_text = component_field(header, :text)
    body_text   = component_field(body, :text)

    header_placeholders = placeholders_for(header_text)
    body_placeholders   = placeholders_for(body_text)

    unsupported_reason = unsupported_reason_for(components:, header:, buttons:)

    {
      name:               template.name,
      language:           template.language,
      category:           template.category,
      header:             header_text,
      header_format:      component_field(header, :format),
      body:               body_text,
      footer:             component_field(footer, :text),
      buttons:            button_texts(buttons),
      parameter_format:   parameter_format(template, header_placeholders + body_placeholders),
      placeholders:       {
        header: header_placeholders,
        body:   body_placeholders,
      },
      supported:          unsupported_reason.nil?,
      unsupported_reason: unsupported_reason,
    }
  end

  def unsupported_reason_for(components:, header:, buttons:)
    return __('Enthält ein Karussell und wird noch nicht unterstützt.') if components.any? { |c| component_type(c) == 'CAROUSEL' }

    if header
      header_format = component_field(header, :format).to_s.upcase
      if UNSUPPORTED_HEADER_FORMATS.include?(header_format)
        return format(__('Enthält einen %s-Header und wird noch nicht unterstützt.'), header_format)
      end
    end

    button_unsupported_reason(buttons)
  end

  def button_unsupported_reason(buttons_component)
    return if !buttons_component

    Array(component_field(buttons_component, :buttons)).each do |button|
      type = component_field(button, :type).to_s.upcase

      return __('Enthält eine OTP-Schaltfläche und wird noch nicht unterstützt.') if type == 'OTP'

      if type == 'URL' && dynamic_url_button?(button)
        return __('Enthält eine URL-Schaltfläche mit Platzhalter und wird noch nicht unterstützt.')
      end
    end

    nil
  end

  def dynamic_url_button?(button)
    url = component_field(button, :url)
    return false if url.blank?

    url.include?('{{')
  end

  def button_texts(buttons_component)
    return [] if !buttons_component

    Array(component_field(buttons_component, :buttons))
      .filter_map { |button| component_field(button, :text) }
  end

  def placeholders_for(text)
    return [] if text.blank?

    text.scan(PLACEHOLDER_PATTERN).flatten
  end

  # A template-level `parameter_format` field ('POSITIONAL'/'NAMED') exists in
  # Meta's newer template API. It is not in the attribute list this task
  # confirmed for WhatsappSdk::Resource::Template (id, status, category,
  # language, name, components_json), so this only uses it if the object
  # happens to expose it, and otherwise infers from the placeholders
  # themselves: numeric ({{1}}) means POSITIONAL, anything else ({{name}})
  # means NAMED.
  def parameter_format(template, placeholders)
    explicit = component_field(template, :parameter_format)
    return explicit.to_s.upcase if explicit.present?

    return 'NAMED' if placeholders.any? { |p| p !~ /\A\d+\z/ }

    'POSITIONAL'
  end

  # Meta's template components are worked with here only as "something that
  # might be a Hash with string or symbol keys, or might be an SDK resource
  # object with matching methods" -- this is the one place that has to know
  # that ambiguity, so callers can just ask for a field by name.
  def component_field(component, key)
    return if component.nil?

    if component.is_a?(Hash)
      component[key.to_s] || component[key.to_sym]
    elsif component.respond_to?(key)
      component.public_send(key)
    end
  end

  def component_type(component)
    component_field(component, :type).to_s.upcase
  end
end
