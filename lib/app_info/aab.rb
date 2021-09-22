# frozen_string_literal: true

require 'app_info/aab/manifest'
require 'image_size'
require 'forwardable'

module AppInfo
  # Parse APK file
  class AAB
    extend Forwardable

    attr_reader :file

    # APK Devices
    module Device
      PHONE   = 'Phone'
      TABLET  = 'Tablet'
      WATCH   = 'Watch'
      TV      = 'Television'
    end

    def initialize(file)
      @file = file
    end

    def size(human_size: false)
      AppInfo::Util.file_size(@file, human_size)
    end

    def os
      AppInfo::Platform::ANDROID
    end
    alias file_type os

    # def_delegators :manifest, :version_name, :package_name,
    #                :use_permissions, :components

    # alias release_version version_name
    # alias identifier package_name
    # alias bundle_id package_name

    # def version_code
    #   manifest.version_code.to_s
    # end
    # alias build_version version_code

    # def name
    #   manifest.label || resource.find('@string/app_name')
    # end

    # def device_type
    #   if wear?
    #     Device::WATCH
    #   elsif tv?
    #     Device::TV
    #   else
    #     Device::PHONE
    #   end
    # end

    # # TODO: find a way to detect
    # # def tablet?
    # #   resource
    # # end

    # def wear?
    #   use_features.include?('android.hardware.type.watch')
    # end

    # def tv?
    #   use_features.include?('android.software.leanback')
    # end

    # def min_sdk_version
    #   manifest.min_sdk_ver
    # end
    # alias min_os_version min_sdk_version

    # def target_sdk_version
    #   manifest.doc
    #           .elements['/manifest/uses-sdk']
    #           .attributes['targetSdkVersion']
    #           .to_i
    # end

    # def use_features
    #   manifest_values('/manifest/uses-feature')
    # end

    # def signs
    #   apk.signs.each_with_object([]) do |(path, sign), obj|
    #     obj << Sign.new(path, sign)
    #   end
    # end

    # def certificates
    #   apk.certificates.each_with_object([]) do |(path, certificate), obj|
    #     obj << Certificate.new(path, certificate)
    #   end
    # end

    # def activities
    #   components.select { |c| c.type == 'activity' }
    # end

    # def services
    #   components.select { |c| c.type == 'service' }
    # end

    def manifest
      io = zip.read(zip.find_entry('base/manifest/AndroidManifest.xml'))
      @manifest ||= AppInfo::Manifest.parse(io, resources)
    end

    def resources
      io = zip.read(zip.find_entry('base/resources.pb'))
      @resources ||= AppInfo::Resources.parse(io)
    end

    def zip
      @zip ||= Zip::File.open(@file)
    end

    # def icons
    #   @icons ||= apk.icon.each_with_object([]) do |(path, data), obj|
    #     icon_name = File.basename(path)
    #     icon_path = File.join(contents, File.dirname(path))
    #     icon_file = File.join(icon_path, icon_name)
    #     FileUtils.mkdir_p icon_path
    #     File.write(icon_file, data, encoding: Encoding::BINARY)

    #     obj << {
    #       name: icon_name,
    #       file: icon_file,
    #       dimensions: ImageSize.path(icon_file).size
    #     }
    #   end
    # end

    def clear!
      return unless @contents

      FileUtils.rm_rf(@contents)

      @aab = nil
      @contents = nil
      @icons = nil
      @app_path = nil
      @info = nil
    end

    def contents
      @contents ||= File.join(Dir.mktmpdir, "AppInfo-android-#{SecureRandom.hex}")
    end

    private

    def manifest_values(path, key = 'name')
      values = []
      manifest.doc.each_element(path) do |elem|
        values << elem.attributes[key]
      end
      values.uniq
    end

    # Android Certificate
    class Certificate
      attr_reader :path, :certificate

      def initialize(path, certificate)
        @path = path
        @certificate = certificate
      end
    end

    # Android Sign
    class Sign
      attr_reader :path, :sign

      def initialize(path, sign)
        @path = path
        @sign = sign
      end
    end
  end
end
