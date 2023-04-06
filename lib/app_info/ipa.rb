# frozen_string_literal: true

require 'macho'
require 'fileutils'
require 'forwardable'
require 'cfpropertylist'

module AppInfo
  # IPA parser
  class IPA < File
    extend Forwardable
    include Helper::HumanFileSize
    include Helper::Archive

    attr_reader :file

    # iOS Export types
    module ExportType
      DEBUG   = 'Debug'
      ADHOC   = 'AdHoc'
      ENTERPRISE = 'Enterprise'
      RELEASE = 'Release'
      UNKOWN  = nil

      INHOUSE = 'Enterprise' # Rename and Alias to enterprise
    end

    # return file size
    # @example Read file size in integer
    #   aab.size                    # => 3618865
    #
    # @example Read file size in human readabale
    #   aab.size(human_size: true)  # => '3.45 MB'
    #
    # @param [Boolean] human_size Convert integer value to human readable.
    # @return [Integer, String]
    def size(human_size: false)
      file_to_human_size(@file, human_size: human_size)
    end

    # @return [Symbol] {Platform}
    def platform
      Platform::APPLE
    end

    # @!method device
    #   @see InfoPlist#device
    # @!method opera_system
    #   @see InfoPlist#opera_system
    # @!method iphone?
    #   @see InfoPlist#iphone?
    # @!method ipad?
    #   @see InfoPlist#ipad?
    # @!method universal?
    #   @see InfoPlist#universal?
    # @!method build_version
    #   @see InfoPlist#build_version
    # @!method name
    #   @see InfoPlist#name
    # @!method release_version
    #   @see InfoPlist#release_version
    # @!method identifier
    #   @see InfoPlist#identifier
    # @!method bundle_id
    #   @see InfoPlist#bundle_id
    # @!method display_name
    #   @see InfoPlist#display_name
    # @!method bundle_name
    #   @see InfoPlist#bundle_name
    # @!method min_sdk_version
    #   @see InfoPlist#min_sdk_version
    # @!method min_os_version
    #   @see InfoPlist#min_os_version
    def_delegators :info, :device, :opera_system, :iphone?, :ipad?, :universal?,
                   :build_version, :name, :release_version, :identifier, :bundle_id,
                   :display_name, :bundle_name, :min_sdk_version, :min_os_version

    # @!method devices
    #   @see MobileProvision#devices
    # @!method team_name
    #   @see MobileProvision#team_name
    # @!method team_identifier
    #   @see MobileProvision#team_identifier
    # @!method profile_name
    #   @see MobileProvision#profile_name
    # @!method expired_date
    #   @see MobileProvision#expired_date
    def_delegators :mobileprovision, :devices, :team_name, :team_identifier,
                   :profile_name, :expired_date

    # @return [String, nil]
    def distribution_name
      "#{profile_name} - #{team_name}" if profile_name && team_name
    end

    # @return [String]
    def release_type
      if stored?
        ExportType::RELEASE
      else
        build_type
      end
    end

    # @return [String]
    def build_type
      if mobileprovision?
        if devices
          ExportType::ADHOC
        else
          ExportType::ENTERPRISE
        end
      else
        ExportType::DEBUG
      end
    end

    # @return [MachO]
    def archs
      return unless ::File.exist?(bundle_path)

      file = MachO.open(bundle_path)
      case file
      when MachO::MachOFile
        [file.cpusubtype]
      else
        file.machos.each_with_object([]) do |arch, obj|
          obj << arch.cpusubtype
        end
      end
    end
    alias architectures archs

    # Full icons metadata
    # @example
    #   aab.icons
    #   # => [
    #   #   {
    #   #     name: 'icon.png',
    #   #     file: '/path/to/icon.png',
    #   #     uncrushed_file: '/path/to/uncrushed_icon.png',
    #   #     dimensions: [64, 64]
    #   #   },
    #   #   {
    #   #     name: 'icon1.png',
    #   #     file: '/path/to/icon1.png',
    #   #     uncrushed_file: '/path/to/uncrushed_icon1.png',
    #   #     dimensions: [120, 120]
    #   #   }
    #   # ]
    # @return [Array<Hash{Symbol => String, Array<Integer>}>] icons paths of icons
    def icons(uncrush: true)
      @icons ||= icons_path.each_with_object([]) do |file, obj|
        obj << build_icon_metadata(file, uncrush: uncrush)
      end
    end

    # @return [Boolean]
    def stored?
      !!metadata?
    end

    # @return [Array<Plugin>]
    def plugins
      @plugins ||= Plugin.parse(app_path)
    end

    # @return [Array<Framework>]
    def frameworks
      @frameworks ||= Framework.parse(app_path)
    end

    # force remove developer certificate data from {#mobileprovision} method
    # @return [nil]
    def hide_developer_certificates
      mobileprovision.delete('DeveloperCertificates') if mobileprovision?
    end

    # @return [MobileProvision]
    def mobileprovision
      return unless mobileprovision?
      return @mobileprovision if @mobileprovision

      @mobileprovision = MobileProvision.new(mobileprovision_path)
    end

    # @return [Boolean]
    def mobileprovision?
      ::File.exist?(mobileprovision_path)
    end

    # @return [String]
    def mobileprovision_path
      filename = 'embedded.mobileprovision'
      @mobileprovision_path ||= ::File.join(@file, filename)
      unless ::File.exist?(@mobileprovision_path)
        @mobileprovision_path = ::File.join(app_path, filename)
      end

      @mobileprovision_path
    end

    # @return [CFPropertyList]
    def metadata
      return unless metadata?

      @metadata ||= CFPropertyList.native_types(CFPropertyList::List.new(file: metadata_path).value)
    end

    # @return [Boolean]
    def metadata?
      ::File.exist?(metadata_path)
    end

    # @return [String]
    def metadata_path
      @metadata_path ||= ::File.join(contents, 'iTunesMetadata.plist')
    end

    # @return [String]
    def bundle_path
      @bundle_path ||= ::File.join(app_path, info.bundle_name)
    end

    # @return [InfoPlist]
    def info
      @info ||= InfoPlist.new(info_path)
    end

    # @return [String]
    def info_path
      @info_path ||= ::File.join(app_path, 'Info.plist')
    end

    # @return [String]
    def app_path
      @app_path ||= Dir.glob(::File.join(contents, 'Payload', '*.app')).first
    end

    IPHONE_KEY = 'CFBundleIcons'
    IPAD_KEY = 'CFBundleIcons~ipad'

    # @return [Array<String>]
    def icons_path
      @icons_path ||= lambda {
        icon_keys.each_with_object([]) do |name, icons|
          filenames = info.try(:[], name)
                          .try(:[], 'CFBundlePrimaryIcon')
                          .try(:[], 'CFBundleIconFiles')

          next if filenames.nil? || filenames.empty?

          filenames.each do |filename|
            Dir.glob(::File.join(app_path, "#{filename}*")).find_all.each do |file|
              icons << file
            end
          end
        end
      }.call
    end

    def clear!
      return unless @contents

      FileUtils.rm_rf(@contents)

      @contents = nil
      @app_path = nil
      @info_path = nil
      @info = nil
      @metadata_path = nil
      @metadata = nil
      @icons_path = nil
      @icons = nil
    end

    # @return [String] contents path of contents
    def contents
      @contents ||= unarchive(@file, prefix: 'ios')
    end

    private

    def build_icon_metadata(file, uncrush: true)
      uncrushed_file = uncrush ? uncrush_png(file) : nil

      {
        name: ::File.basename(file),
        file: file,
        uncrushed_file: uncrushed_file,
        dimensions: PngUncrush.dimensions(file)
      }
    end

    # Uncrush png to normal png file (iOS)
    def uncrush_png(src_file)
      dest_file = tempdir(src_file, prefix: 'uncrushed')
      PngUncrush.decompress(src_file, dest_file)
      ::File.exist?(dest_file) ? dest_file : nil
    end

    def icon_keys
      @icon_keys ||= case device
                     when Device::IPHONE
                       [IPHONE_KEY]
                     when Device::IPAD
                       [IPAD_KEY]
                     when Device::UNIVERSAL
                       [IPHONE_KEY, IPAD_KEY]
                     end
    end
  end
end
