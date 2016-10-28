require 'net/ldap/dn'

module EE
  module Gitlab
    module LDAP
      module Sync
        class Proxy
          attr_reader :provider, :adapter

          # Open a connection and run all queries through it.
          # It's more efficient than the default of opening/closing per LDAP query.
          def self.open(provider, &block)
            ::Gitlab::LDAP::Adapter.open(provider) do |adapter|
              block.call(self.new(provider, adapter))
            end
          end

          def initialize(provider, adapter)
            @adapter = adapter
            @provider = provider
          end

          # Cache LDAP group member DNs so we don't query LDAP groups more than once.
          def dns_for_group_cn(group_cn)
            @dns_for_group_cn ||= Hash.new { |h, k| h[k] = ldap_group_member_dns(k) }
            @dns_for_group_cn[group_cn]
          end

          # Cache user DN so we don't generate excess queries to map UID to DN
          def dn_for_uid(uid)
            @dn_for_uid ||= Hash.new { |h, k| h[k] = member_uid_to_dn(k) }
            @dn_for_uid[uid]
          end

          private

          def ldap_group_member_dns(ldap_group_cn)
            ldap_group = LDAP::Group.find_by_cn(ldap_group_cn, adapter)
            unless ldap_group.present?
              logger.warn { "Cannot find LDAP group with CN '#{ldap_group_cn}'. Skipping" }
              return []
            end

            member_dns = ldap_group.member_dns
            if member_dns.empty?
              # Group must be empty
              return [] unless ldap_group.memberuid?

              members = ldap_group.member_uids
              member_dns = members.map { |uid| dn_for_uid(uid) }
            end

            # Various lookups in this method could return `nil` values.
            # Compact the array to remove those entries
            member_dns.compact!

            ensure_full_dns!(member_dns)

            logger.debug { "Members in '#{ldap_group.name}' LDAP group: #{member_dns}" }

            # Various lookups in this method could return `nil` values.
            # Compact the array to remove those entries
            member_dns
          end

          # At least one customer reported that their LDAP `member` values contain
          # only `uid=username` and not the full DN. This method allows us to
          # account for that. See gitlab-ee#442
          def ensure_full_dns!(dns)
            dns.map! do |dn|
              begin
                parsed_dn = Net::LDAP::DN.new(dn).to_a
              rescue RuntimeError => e
                # Net::LDAP raises a generic RuntimeError. Bad library! Bad!
                logger.error { "Found malformed DN: '#{dn}'. Skipping. #{e.message}" }
                next
              end

              final_dn =
                # If there is more than one key/value set we must have a full DN,
                # or at least the probability is higher.
                if parsed_dn.count > 2
                  dn
                elsif parsed_dn[0] == 'uid'
                  dn_for_uid(parsed_dn[1])
                else
                  logger.warn { "Found potentially malformed/incomplete DN: '#{dn}'" }
                  dn
                end

              clean_encoding(final_dn)
            end

            # Remove `nil` values generated by the rescue above.
            dns.compact!
          end

          # net-ldap only returns ASCII-8BIT and does not support UTF-8 out-of-the-box:
          # https://github.com/ruby-ldap/ruby-net-ldap/issues/4
          def clean_encoding(dn)
            begin
              dn.force_encoding('UTF-8')
            rescue
              dn
            end
          end

          def member_uid_to_dn(uid)
            identity = Identity.find_by(provider: provider, secondary_extern_uid: uid)

            if identity.present?
              # Use the DN on record in GitLab when it's available
              identity.extern_uid
            else
              ldap_user = ::Gitlab::LDAP::Person.find_by_uid(uid, adapter)

              # Can't find a matching user
              return nil unless ldap_user.present?

              # Update user identity so we don't have to go through this again
              update_identity(ldap_user.dn, uid)

              ldap_user.dn
            end
          end

          def update_identity(dn, uid)
            identity =
              Identity.find_by(provider: provider, extern_uid: dn)

            # User may not exist in GitLab yet. Skip.
            return unless identity.present?

            identity.secondary_extern_uid = uid
            identity.save
          end

          def logger
            Rails.logger
          end
        end
      end
    end
  end
end
