# frozen_string_literal: true

class ServiceFieldEntity < Grape::Entity
  include RequestAwareEntity

  expose :type, :name, :new_title, :title, :placeholder, :required, :choices, :help

  expose :value do |field|
    # field[:name] is not user input and so can assume is safe
    value = service.public_send(field[:name]) # rubocop:disable GitlabSecurity/PublicSend

    if field[:type] == 'password' && value.present?
      'true'
    elsif field[:type] == 'checkbox'
      ActiveRecord::Type::Boolean.new.deserialize(value).to_s
    else
      value
    end
  end

  private

  def service
    request.service
  end
end
