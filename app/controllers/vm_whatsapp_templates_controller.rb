# "Send an approved template" -- once WhatsApp's 24 hour customer service
# window has closed, Meta only allows a pre-approved message template, not a
# free-form reply. This is the bridge between the ticket zoom's "Vorlage
# senden" button and the Cloud API: list the Business Account's approved
# templates for the ticket's channel, and create+send a filled-in one as a
# normal whatsapp-message article.
#
# Zeitwerk derives the constant from the filename -- see VmAssistantController
# for why "Vm", not "VM", matters here (a casing mismatch only fails at boot,
# not in any test).
class VmWhatsappTemplatesController < ApplicationController
  prepend_before_action :authenticate_and_authorize!

  CACHE_TTL = 5.minutes

  # GET /api/v1/vm_whatsapp/templates?ticket_id=
  def index
    ticket = Ticket.find(params[:ticket_id])
    authorize!(ticket, :follow_up?)

    channel = whatsapp_channel_for(ticket)
    return render_no_channel if !channel

    render json: { templates: ticket_templates(channel) }
  rescue ActiveRecord::RecordNotFound
    render json: { error: __('Ticket wurde nicht gefunden.') }, status: :not_found
  rescue Whatsapp::Client::CloudAPIError => e
    render_cloud_api_error(e, action: 'index')
  end

  # POST /api/v1/vm_whatsapp/templates/send
  #
  # params: { ticket_id, name, language, parameters: { header: [...], body: [...] } }
  # Each entry in `parameters.header`/`parameters.body` is either a plain
  # value, or (required for a NAMED template) a { name, value } object.
  def send_template
    ticket = Ticket.find(params[:ticket_id])
    authorize!(ticket, :follow_up?)

    channel = whatsapp_channel_for(ticket)
    return render_no_channel if !channel

    template = find_template(channel, params[:name].to_s, params[:language].to_s)
    return render json: { error: __('Diese Vorlage wurde nicht gefunden. Bitte die Liste neu laden.') }, status: :unprocessable_content if !template

    if !template[:supported]
      return render json: { error: format(__('Diese Vorlage wird noch nicht unterstützt: %s'), template[:unsupported_reason]) }, status: :unprocessable_content
    end

    header_params = normalize_parameters(params.dig(:parameters, :header))
    body_params   = normalize_parameters(params.dig(:parameters, :body))

    if placeholders_missing?(template, header_params, body_params)
      return render json: { error: __('Bitte alle Platzhalter ausfüllen.') }, status: :unprocessable_content
    end

    article = create_article!(ticket:, template:, header_params:, body_params:)

    render json: { article_id: article.id }, status: :created
  rescue ActiveRecord::RecordNotFound
    render json: { error: __('Ticket wurde nicht gefunden.') }, status: :not_found
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.to_sentence.presence || __('Die Vorlage konnte nicht gesendet werden.') }, status: :unprocessable_content
  rescue Whatsapp::Client::CloudAPIError => e
    render_cloud_api_error(e, action: 'send_template')
  end

  private

  def render_no_channel
    render json: { error: __('Für dieses Ticket ist kein WhatsApp-Kanal hinterlegt.') }, status: :unprocessable_content
  end

  def render_cloud_api_error(error, action:)
    Rails.logger.error "VmWhatsappTemplatesController##{action}: #{error.message}"
    render json: { error: __('Die Vorlagen konnten nicht von WhatsApp geladen werden. Bitte später erneut versuchen.') }, status: :unprocessable_content
  end

  def whatsapp_channel_for(ticket)
    channel_id = ticket.preferences['channel_id']
    return if channel_id.blank?

    channel = Channel.lookup(id: channel_id)
    return if channel.nil?
    return if channel.options[:adapter] != 'whatsapp'

    channel
  end

  def cached_templates(channel)
    Rails.cache.fetch("vm_whatsapp_templates/#{channel.id}", expires_in: CACHE_TTL, skip_nil: true) do
      Whatsapp::Account::Templates
        .new(**channel.options.slice(:access_token, :business_id).symbolize_keys)
        .all
    end
  end

  def find_template(channel, name, language)
    return if name.blank? || language.blank?

    ticket_templates(channel).find { |t| t[:name] == name && t[:language] == language }
  end

  # Marketing templates are not sent from a ticket. Advertising over WhatsApp
  # needs the contact's recorded opt-in, which only the campaign send path
  # checks (against the tenant's consent ledger, right before each send). A
  # ticket has no such check, so an agent could otherwise message a customer
  # who never agreed to advertising, or one who opted out. Utility and
  # authentication templates, the ones that reopen a conversation about the
  # customer's own request, stay available.
  def ticket_templates(channel)
    cached_templates(channel).map do |template|
      next template if template[:category].to_s.upcase != 'MARKETING'

      template.merge(
        supported:          false,
        unsupported_reason: __('Werbevorlage: wird nur über eine Kampagne mit geprüfter Einwilligung versendet, nicht aus dem Ticket.'),
      )
    end
  end

  # Accepts either a plain value ("Max"), or a { name:, value: } object (the
  # shape required for a NAMED template's parameters, per the task spec).
  def normalize_parameters(list)
    Array(list).map do |item|
      if item.is_a?(ActionController::Parameters) || item.is_a?(Hash)
        { name: item[:name].presence, value: item[:value].to_s }
      else
        { name: nil, value: item.to_s }
      end
    end
  end

  def placeholders_missing?(template, header_params, body_params)
    named = template[:parameter_format] == 'NAMED'

    missing_for?(template[:placeholders][:header], header_params, named:) ||
      missing_for?(template[:placeholders][:body], body_params, named:)
  end

  def missing_for?(placeholders, params, named:)
    return false if placeholders.blank?

    if named
      by_name = params.index_by { |p| p[:name] }
      placeholders.any? { |name| by_name[name].blank? || by_name[name][:value].blank? }
    else
      placeholders.each_index.any? { |index| params[index].blank? || params[index][:value].blank? }
    end
  end

  def create_article!(ticket:, template:, header_params:, body_params:)
    Ticket::Article.create!(
      ticket_id:     ticket.id,
      type_id:       Ticket::Article::Type.lookup(name: 'whatsapp message').id,
      sender_id:     Ticket::Article::Sender.lookup(name: 'Agent').id,
      internal:      false,
      content_type:  'text/plain',
      body:          render_text(template, header_params, body_params),
      preferences:   {
        'vm_whatsapp_template' => {
          'name'            => template[:name],
          'language'        => template[:language],
          'components_json' => build_components_json(template, header_params, body_params),
        },
      },
      created_by_id: current_user.id,
      updated_by_id: current_user.id,
    )
  end

  def build_components_json(template, header_params, body_params)
    components = []

    if template[:placeholders][:header].present?
      components << { 'type' => 'header', 'parameters' => build_parameters(template, header_params) }
    end

    if template[:placeholders][:body].present?
      components << { 'type' => 'body', 'parameters' => build_parameters(template, body_params) }
    end

    components
  end

  def build_parameters(template, params)
    if template[:parameter_format] == 'NAMED'
      params.map { |p| { 'type' => 'text', 'parameter_name' => p[:name], 'text' => p[:value] } }
    else
      params.map { |p| { 'type' => 'text', 'text' => p[:value] } }
    end
  end

  # The article's own rendered text -- what shows up in the ticket, and what
  # actually gets sent (WhatsApp renders the template with these same
  # parameters on its side; this is our record of what that says).
  def render_text(template, header_params, body_params)
    [
      substitute(template[:header], template[:placeholders][:header], header_params, template[:parameter_format]),
      substitute(template[:body], template[:placeholders][:body], body_params, template[:parameter_format]),
      template[:footer],
    ].compact_blank.join("\n\n")
  end

  def substitute(text, placeholders, params, parameter_format)
    return if text.blank?
    return text if placeholders.blank?

    result = text.dup

    if parameter_format == 'NAMED'
      by_name = params.index_by { |p| p[:name] }
      placeholders.each do |name|
        result = result.gsub("{{#{name}}}", by_name[name]&.dig(:value).to_s)
      end
    else
      placeholders.each_with_index do |_placeholder, index|
        result = result.gsub("{{#{index + 1}}}", params[index]&.dig(:value).to_s)
      end
    end

    result
  end
end
