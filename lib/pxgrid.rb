require "pxgrid/version"
require "json"
require "faraday"

module Pxgrid
  class Client
    attr_accessor :nodename, :username
    @nodename = ""
    @client = ""
    @username = ""
    @password = ""
    def initialize(pxgrid_ip, nodename, credentials = {})
      @nodename = nodename
      @client = Faraday.new("https://#{pxgrid_ip}:8910/pxgrid/") do |conn|
        conn.adapter Faraday.default_adapter
        conn.ssl[:verify] = false
        conn.headers["Accept"] = "application/json"
        conn.headers["Content-Type"] = "application/json"
      end
      puts credentials
      if credentials && credentials[:username] && credentials[:password]
        # Looks like we have an account. Validate the account.
        @username = credentials[:username]
        @password = credentials[:password]
      else
        # Don't have credentials. Create the account in pxGrid.
        # Create an account and get the username and password
        params = {"nodeName": nodename}
        response = @client.post("control/AccountCreate", params.to_json)
        if response.success?
          response = JSON.parse(response.body)
          @username = response["userName"]
          @password = response["password"]
        else
          raise "AccountCreationError"
        end
      end

      # Save the credentials as part of the connection
      @client.basic_auth(@username, @password)
      return @client
    end

    def activate
      params = {"nodeName": @nodename}
      # Validate the credentials and activate it.
      response = JSON.parse(@client.post("control/AccountActivate", params.to_json).body)
      if response["accountState"] == "PENDING"
        # Approve the account in pxGrid
        return {"status": "PENDING", "description": "Account is pending approval. Approve it within pxGrid"}
      elsif response["accountState"] == "ENABLED"
        # Account is approved.
        return {"status": "ENABLED", "description": "Account is ready to be used"}
      else
        return {"status": "DISABLED", "description": "Account is disabled in pxGrid. Please enable account and try again."}
      end
    end

    def serviceLookup(service)
      params = {"name": service}
      services = JSON.parse(@client.post("control/ServiceLookup", params.to_json).body)
    end

    def accessSecret(peerNodeName)
        params = {"peerNodeName": peerNodeName}
        return JSON.parse(@client.post("control/AccessSecret", params.to_json).body)["secret"]
    end
  end

  module ISE
    class Session
      SERVICE = "com.cisco.ise.session"
      @nodeName = ""
      @username = ""
      @password = ""
      @client = ""
      def initialize(pxgrid_client)
        service = pxgrid_client.serviceLookup(SERVICE)["services"].sample
        @nodeName = service["nodeName"]
        @username = pxgrid_client.username
        @password = pxgrid_client.accessSecret(@nodeName)

        @client = Faraday.new(service["properties"]["restBaseUrl"]) do |conn|
          conn.adapter Faraday.default_adapter
          conn.basic_auth @username, @password
          conn.ssl[:verify] = false
          conn.headers["Accept"] = "application/json"
          conn.headers["Content-Type"] = "application/json"
        end
      end

      def getSessions(startTimestamp = "")
        if startTimestamp.empty?
          params = {}
        else
          params = {"startTimestamp": startTimestamp}
        end
        return JSON.parse(@client.post("getSessions", params.to_json).body)["sessions"]
      end
    end
  end
end
