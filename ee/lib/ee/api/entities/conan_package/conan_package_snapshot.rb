# frozen_string_literal: true

module EE
  module API
    module Entities
      module ConanPackage
        class ConanPackageSnapshot < Grape::Entity
          expose :package_snapshot, merge: true
        end
      end
    end
  end
end
