require "base64"
require "json"
require "jwt"
require "net/http"
require "openssl"
require "uri"

# A small App Store Connect API client for the two things fastlane doesn't do:
# finding the build Xcode Cloud made from a given commit, and reading the
# highest version Apple has approved.
# API reference: https://developer.apple.com/documentation/appstoreconnectapi
class AppStoreConnect
  BASE_URL = "https://api.appstoreconnect.apple.com".freeze
  MAX_RUN_PAGES = 10

  class Error < StandardError; end

  def initialize(key_id:, issuer_id:, key_p8_base64:, base_url: BASE_URL)
    @key_id = key_id
    @issuer_id = issuer_id
    @key = OpenSSL::PKey::EC.new(Base64.decode64(key_p8_base64))
    @base_url = base_url
  end

  def app_id(bundle_id)
    apps = get("/v1/apps", "filter[bundleId]" => bundle_id, "limit" => 1)["data"]
    raise Error, "No app with bundle ID #{bundle_id} in App Store Connect." if apps.empty?
    apps.first["id"]
  end

  # Where the build for `commit` stands. Returns a hash with :state, one of
  #   :ready      -> also :version, :build_number, :build_id, :run_number
  #   :waiting    -> Xcode Cloud hasn't started, is still building, or App Store Connect is processing
  #   :failed     -> the build run failed, or every build it made is invalid or expired
  # and a :message to show.
  def xcode_cloud_build(app_id:, commit:)
    product = get("/v1/apps/#{app_id}/ciProduct")["data"]
    raise Error, "This app has no Xcode Cloud product. Set up the Xcode Cloud workflow first." unless product

    runs = build_runs(product["id"]).select do |run|
      attributes = run["attributes"]
      attributes.dig("sourceCommit", "commitSha") == commit && !attributes["isPullRequestBuild"]
    end
    if runs.empty?
      return { state: :waiting, message: "Xcode Cloud hasn't started a build of #{commit[0, 7]} yet." }
    end

    runs.sort_by! { |run| -run["attributes"]["number"].to_i }
    problems = []
    runs.each do |run|
      attributes = run["attributes"]
      number = attributes["number"]
      unless attributes["executionProgress"] == "COMPLETE"
        return { state: :waiting, message: "Xcode Cloud build #{number} of #{commit[0, 7]} is #{attributes['executionProgress'].to_s.downcase}." }
      end
      unless attributes["completionStatus"] == "SUCCEEDED"
        problems << "Xcode Cloud build #{number} ended #{attributes['completionStatus'].to_s.downcase}."
        next
      end

      builds = get("/v1/ciBuildRuns/#{run['id']}/builds")["data"]
      if builds.empty?
        problems << "Xcode Cloud build #{number} uploaded nothing. Check that the workflow archives for TestFlight."
        next
      end
      builds.each do |build|
        state = build["attributes"]["processingState"]
        build_number = build["attributes"]["version"]
        if state == "PROCESSING"
          return { state: :waiting, message: "App Store Connect is still processing build #{build_number}." }
        elsif state != "VALID"
          problems << "Build #{build_number} is #{state.to_s.downcase}."
        elsif build["attributes"]["expired"]
          problems << "Build #{build_number} has expired in TestFlight (builds last 90 days). Push to main for a fresh build."
        else
          version = get("/v1/builds/#{build['id']}/preReleaseVersion")["data"]["attributes"]["version"]
          return {
            state: :ready,
            message: "Found #{version} (#{build_number}) from Xcode Cloud build #{number}.",
            version: version,
            build_number: build_number,
            build_id: build["id"],
            run_number: number,
          }
        end
      end
    end
    { state: :failed, message: "No usable build of #{commit[0, 7]}. #{problems.join(' ')}" }
  end

  # Version states that mean Apple approved it. App Store Connect rejects new
  # builds for an approved version, so a release must be higher than these.
  APPROVED_STATES = %w[
    ACCEPTED PENDING_APPLE_RELEASE PENDING_DEVELOPER_RELEASE PROCESSING_FOR_APP_STORE
    PROCESSING_FOR_DISTRIBUTION READY_FOR_DISTRIBUTION READY_FOR_SALE REPLACED_WITH_NEW_VERSION
    DEVELOPER_REMOVED_FROM_SALE REMOVED_FROM_SALE
  ].freeze

  # The highest version Apple has approved, or nil before the first release.
  def approved_version(app_id)
    versions = get("/v1/apps/#{app_id}/appStoreVersions", "filter[platform]" => "IOS", "limit" => 200)["data"]
    versions
      .select { |version| APPROVED_STATES.include?(version["attributes"]["appVersionState"] || version["attributes"]["appStoreState"]) }
      .map { |version| version["attributes"]["versionString"] }
      .max_by { |string| Gem::Version.new(string) }
  end

  private

  def build_runs(product_id)
    runs = []
    url = "/v1/ciProducts/#{product_id}/buildRuns"
    params = { "limit" => 200 }
    MAX_RUN_PAGES.times do
      page = get(url, params)
      runs.concat(page["data"])
      url = page.dig("links", "next")
      break unless url
      params = {}
    end
    runs
  end

  def get(path_or_url, params = {})
    uri = URI(path_or_url.start_with?("http") ? path_or_url : "#{@base_url}#{path_or_url}")
    uri.query = URI.encode_www_form(params) unless params.empty?
    request = Net::HTTP::Get.new(uri)
    request["Authorization"] = "Bearer #{token}"
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") { |http| http.request(request) }
    unless response.is_a?(Net::HTTPSuccess)
      details = begin
        JSON.parse(response.body)["errors"].map { |error| error["detail"] || error["title"] }.join(" ")
      rescue StandardError
        response.body.to_s[0, 300]
      end
      raise Error, "App Store Connect answered #{response.code} for #{uri.path}: #{details}"
    end
    JSON.parse(response.body)
  end

  # Tokens may live up to 20 minutes; make a new one every 10.
  def token
    now = Time.now.to_i
    if @token.nil? || now > @token_expires - 600
      @token_expires = now + 1200
      payload = { iss: @issuer_id, iat: now, exp: @token_expires, aud: "appstoreconnect-v1" }
      @token = JWT.encode(payload, @key, "ES256", { kid: @key_id, typ: "JWT" })
    end
    @token
  end
end
