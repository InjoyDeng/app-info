# frozen_string_literal: true

require 'openssl'
require 'cfpropertylist'

module AppInfo
  # Apple code signing: provisioning profile parser
  # @see https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles
  class MobileProvision < File
    # @return [Symbol] {Platform}
    def platform
      Platform::APPLE
    end

    # @return [Symbol] {OperaSystem}
    def opera_system
      case opera_systems[0]
      when :macos
        OperaSystem::MACOS
      when :ios
        OperaSystem::IOS
      else
        raise NotImplementedError, "Unkonwn opera_system: #{opera_systems[0]}"
      end
    end

    # @return [String, nil]
    def name
      mobileprovision.try(:[], 'Name')
    end

    # @return [String, nil]
    def app_name
      mobileprovision.try(:[], 'AppIDName')
    end

    # @return [Symbol, nil]
    def type
      return :development if development?
      return :adhoc if adhoc?
      return :appstore if appstore?
      return :enterprise if enterprise?
    end

    # @return [Array<Symbol>]
    def opera_systems
      return unless platforms = mobileprovision.try(:[], 'Platform')

      platforms.map do |v|
        v = 'macOS' if v == 'OSX'
        v.downcase.to_sym
      end
    end

    # @return [Array<String>, nil]
    def devices
      mobileprovision.try(:[], 'ProvisionedDevices')
    end

    # @return [String, nil]
    def team_identifier
      mobileprovision.try(:[], 'TeamIdentifier')
    end

    # @return [String, nil]
    def team_name
      mobileprovision.try(:[], 'TeamName')
    end

    # @return [String, nil]
    def profile_name
      mobileprovision.try(:[], 'Name')
    end

    # @return [String, nil]
    def created_date
      mobileprovision.try(:[], 'CreationDate')
    end

    # @return [String, nil]
    def expired_date
      mobileprovision.try(:[], 'ExpirationDate')
    end

    # @return [Array<String>, nil]
    def entitlements
      mobileprovision.try(:[], 'Entitlements')
    end

    # return developer certificates.
    #
    # @deprecated Use {#certificates} instead of this method.
    def developer_certs
      certificates
    end

    # return developer certificates.
    #
    # @return [Array<Certificate>]
    def certificates
      certs = mobileprovision.try(:[], 'DeveloperCertificates')
      return if certs.empty?

      certs.each_with_object([]) do |cert_data, obj|
        obj << Certificate.parse(cert_data)
      end
    end

    # Detect is development type of mobileprovision
    #
    # @see https://stackoverflow.com/questions/1003066/what-does-get-task-allow-do-in-xcode
    # @return [Boolea]
    def development?
      case opera_system
      when OperaSystem::IOS
        entitlements['get-task-allow'] == true
      when OperaSystem::MACOS
        !devices.nil?
      else
        raise Error, "Not implement with opera_system: #{opera_system}"
      end
    end

    # Detect app store type
    #
    # @see https://developer.apple.com/library/archive/qa/qa1830/_index.html
    # @return [Boolea]
    def appstore?
      case opera_system
      when OperaSystem::IOS
        !development? && entitlements.key?('beta-reports-active')
      when OperaSystem::MACOS
        !development?
      else
        raise Error, "Not implement with opera_system: #{opera_system}"
      end
    end

    # @return [Boolea]
    def adhoc?
      return false if opera_system == OperaSystem::MACOS # macOS no need adhoc

      !development? && !devices.nil?
    end

    # @return [Boolea]
    def enterprise?
      return false if opera_system == OperaSystem::MACOS # macOS no need adhoc

      !development? && !adhoc? && !appstore?
    end
    alias inhouse? enterprise?

    # Enabled Capabilites
    #
    # @see https://developer.apple.com/support/app-capabilities/
    # @return [Array<String>]
    def enabled_capabilities
      capabilities = []
      capabilities << 'In-App Purchase' << 'GameKit' if adhoc? || appstore?

      entitlements.each do |key, _|
        case key
        when 'aps-environment'
          capabilities << 'Push Notifications'
        when 'com.apple.developer.applesignin'
          capabilities << 'Sign In with Apple'
        when 'com.apple.developer.siri'
          capabilities << 'SiriKit'
        when 'com.apple.security.application-groups'
          capabilities << 'App Groups'
        when 'com.apple.developer.associated-domains'
          capabilities << 'Associated Domains'
        when 'com.apple.developer.default-data-protection'
          capabilities << 'Data Protection'
        when 'com.apple.developer.networking.networkextension'
          capabilities << 'Network Extensions'
        when 'com.apple.developer.networking.vpn.api'
          capabilities << 'Personal VPN'
        when 'com.apple.developer.healthkit',
            'com.apple.developer.healthkit.access'
          capabilities << 'HealthKit' unless capabilities.include?('HealthKit')
        when 'com.apple.developer.icloud-services',
            'com.apple.developer.icloud-container-identifiers'
          capabilities << 'iCloud' unless capabilities.include?('iCloud')
        when 'com.apple.developer.in-app-payments'
          capabilities << 'Apple Pay'
        when 'com.apple.developer.homekit'
          capabilities << 'HomeKit'
        when 'com.apple.developer.user-fonts'
          capabilities << 'Fonts'
        when 'com.apple.developer.pass-type-identifiers'
          capabilities << 'Wallet'
        when 'inter-app-audio'
          capabilities << 'Inter-App Audio'
        when 'com.apple.developer.networking.multipath'
          capabilities << 'Multipath'
        when 'com.apple.developer.authentication-services.autofill-credential-provider'
          capabilities << 'AutoFill Credential Provider'
        when 'com.apple.developer.networking.wifi-info'
          capabilities << 'Access WiFi Information'
        when 'com.apple.external-accessory.wireless-configuration'
          capabilities << 'Wireless Accessory Configuration'
        when 'com.apple.developer.kernel.extended-virtual-addressing'
          capabilities << 'Extended Virtual Address Space'
        when 'com.apple.developer.nfc.readersession.formats'
          capabilities << 'NFC Tag Reading'
        when 'com.apple.developer.ClassKit-environment'
          capabilities << 'ClassKit'
        when 'com.apple.developer.networking.HotspotConfiguration'
          capabilities << 'Hotspot'
        when 'com.apple.developer.devicecheck.appattest-environment'
          capabilities << 'App Attest'
        when 'com.apple.developer.coremedia.hls.low-latency'
          capabilities << 'Low Latency HLS'
        when 'com.apple.developer.associated-domains.mdm-managed'
          capabilities << 'MDM Managed Associated Domains'
        # macOS Only
        when 'com.apple.developer.maps'
          capabilities << 'Maps'
        when 'com.apple.developer.system-extension.install'
          capabilities << 'System Extension'
        when 'com.apple.developer.networking.custom-protocol'
          capabilities << 'Custom Network Protocol'
        end
      end

      capabilities
    end

    # @return [String, nil]
    def [](key)
      mobileprovision.try(:[], key.to_s)
    end

    # @return [Boolea]
    def empty?
      mobileprovision.nil?
    end

    # @return [CFPropertyList]
    def mobileprovision
      return @mobileprovision = nil unless ::File.exist?(@file)

      data = ::File.read(@file)
      data = strip_plist_wrapper(data) unless bplist?(data)
      list = CFPropertyList::List.new(data: data).value
      @mobileprovision = CFPropertyList.native_types(list)
    rescue CFFormatError
      @mobileprovision = nil
    end

    def method_missing(method_name, *args, &block)
      mobileprovision.try(:[], method_name.to_s.ai_camelcase) ||
        mobileprovision.send(method_name) ||
        super
    end

    def respond_to_missing?(method_name, *args)
      mobileprovision.key?(method_name.to_s.ai_camelcase) ||
        mobileprovision.respond_to?(method_name) ||
        super
    end

    private

    def bplist?(raw)
      raw[0..5] == 'bplist'
    end

    def strip_plist_wrapper(raw)
      end_tag = '</plist>'
      start_point = raw.index('<?xml version=')
      end_point = raw.index(end_tag) + end_tag.size - 1
      raw[start_point..end_point]
    end
  end
end
