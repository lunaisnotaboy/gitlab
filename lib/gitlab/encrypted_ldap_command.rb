# frozen_string_literal: true

# rubocop:disable Rails/Output
module Gitlab
  class EncryptedLdapCommand
    class << self
      def write(contents)
        encrypted = Gitlab::Auth::Ldap::Config.encrypted_secrets
        return unless validate_config(encrypted)

        validate_contents(contents)
        encrypted.write(contents)

        puts "File encrypted and saved."
      rescue Interrupt
        puts "Aborted changing file: nothing saved."
      rescue ActiveSupport::MessageEncryptor::InvalidMessage
        puts "Couldn't decrypt #{encrypted.content_path}. Perhaps you passed the wrong key?"
      end

      def edit
        encrypted = Gitlab::Auth::Ldap::Config.encrypted_secrets
        return unless validate_config(encrypted)

        editor = ENV['EDITOR'] || 'editor'
        temp_file = Tempfile.new(File.basename(encrypted.content_path), File.dirname(encrypted.content_path))

        encrypted.change do |contents|
          contents = encrypted_file_template unless File.exist?(encrypted.content_path)
          File.write(temp_file.path, contents)
          system(editor, temp_file.path)
          changes = File.read(temp_file.path)
          validate_contents(changes)
          changes
        end

        puts "File encrypted and saved."
      rescue Interrupt
        puts "Aborted changing file: nothing saved."
      rescue ActiveSupport::MessageEncryptor::InvalidMessage
        puts "Couldn't decrypt #{encrypted.content_path}. Perhaps you passed the wrong key?"
      ensure
        temp_file&.unlink
      end

      def show
        encrypted = Gitlab::Auth::Ldap::Config.encrypted_secrets
        return unless validate_config(encrypted)

        puts encrypted.read.presence || "File '#{encrypted.content_path}' does not exist. Use `rake gitlab:ldap:secret:edit` to change that."
      rescue ActiveSupport::MessageEncryptor::InvalidMessage
        puts "Couldn't decrypt #{encrypted.content_path}. Perhaps you passed the wrong key?"
      end

      private

      def validate_config(encrypted)
        dir_path = File.dirname(encrypted.content_path)

        unless File.exist?(dir_path)
          puts "Directory #{dir_path} does not exist. Create the directory and try again."
          return false
        end

        if encrypted.key.nil?
          puts "Missing encryption key enc_settings_key_base."
          return false
        end

        true
      end

      def validate_contents(contents)
        config = YAML.safe_load(contents, permitted_classes: [Symbol])
        puts "WARNING: Content was not a valid LDAP secret yml file." if config.nil? || !config.is_a?(Hash)
        contents
      end

      def encrypted_file_template
        <<~YAML
          # main:
          #   password: '123'
          #   user_bn: 'gitlab-adm'
        YAML
      end
    end
  end
end
# rubocop:enable Rails/Output
