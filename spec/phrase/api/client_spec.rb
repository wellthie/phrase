require 'spec_helper'
require 'phrase'
require 'phrase/api'

describe Phrase::Api::Client do
  let(:auth_token) { "secret123" }

  subject {
    Phrase::Api::Client.new(auth_token)
  }

  describe "#initialize" do
    it "should set an auth token" do
      client = Phrase::Api::Client.new(auth_token)
      client.auth_token.should == "secret123"
    end

    it "should raise an error if auth token was set to nil" do
      lambda {
        Phrase::Api::Client.new(nil)
      }.should raise_error "No auth token specified!"
    end

    it "should raise an error if auth token was empty string" do
      lambda {
        Phrase::Api::Client.new("")
      }.should raise_error "No auth token specified!"
    end
  end

  describe "#fetch_locales" do
    context "request was successful" do
      it "should return a list of locale data" do
        VCR.use_cassette('fetch list of locales') do
          result = subject.fetch_locales
          result.should be_a(Array)
          result.first[:id].should > 0
          result.first[:name].should be_a String
          result.first[:code].should be_a String
        end
      end
    end

    context "an error occured" do
      before(:each) do
        subject.stub(:display_api_error)
      end

      it "should display the error" do
        VCR.use_cassette('fetch list of locales with invalid auth token') do
          subject.instance_variable_set(:@auth_token, "invalidtoken")
          lambda {
            subject.fetch_locales
          }.should raise_error Phrase::Api::Exceptions::Unauthorized
        end
      end
    end
  end

  describe "#fetch_blacklisted_keys" do
    it "should return a list of blacklisted keys" do
      VCR.use_cassette('fetch list of blacklisted keys') do
        result = subject.fetch_blacklisted_keys
        result.should be_a(Array)
      end
    end
  end

  describe "#list_tags" do
    it "should return a list of all tags" do
      VCR.use_cassette('fetch list of tags') do
        result = subject.list_tags
        result.should be_a(Array)
      end
    end
  end

  describe "#find_keys_by_name" do
    it "should return an array" do
      VCR.use_cassette('find translation keys by name') do
        result = subject.find_keys_by_name(["lorem", "ipsum"])
        result.should be_a(Array)
      end
    end
  end

  describe "#translate" do
    it "should raise an exception if the key is blank" do
      lambda {
        subject.translate("")
      }.should raise_error "You must specify a key"
    end

    it "should return a hash" do
      VCR.use_cassette('fetch translate values for key') do
        result = subject.translate("lorem")
        result.should be_a(Hash)
        result.should == {ipsum: "foo"}
      end
    end
  end

  describe "#create_locale" do
    it "should raise an exception if the name is blank" do
      lambda {
        subject.create_locale("")
      }.should raise_error "You must specify a name"
    end

    context "locale already exists" do
      it "should raise an error" do
        VCR.use_cassette('create existing locale') do
          lambda {
            subject.create_locale("en")
          }.should raise_error "Locale en could not be created (Maybe it already exists)"
        end
      end
    end

    context "locale does not exist yet" do
      it "should return true" do
        VCR.use_cassette('create new locale') do
          random_locale = "locale#{rand(1000)}"
          subject.create_locale(random_locale).should be_true
        end
      end
    end
  end

  describe "#make_locale_default" do
    it "should raise an exception if the name is blank" do
      lambda {
        subject.make_locale_default("")
      }.should raise_error "You must specify a name"
    end

    context "locale does not exists" do
      it "should raise an error" do
        VCR.use_cassette('mark unexistant locale as default') do
          lambda {
            subject.make_locale_default("fooooo")
          }.should raise_error "Locale fooooo could not be made the default locale"
        end
      end
    end

    context "locale can be marked as default" do
      before(:all) do
        begin
          VCR.turn_off!
          WebMock.allow_net_connect!
          subject.create_locale("fr")
        rescue Exception => e
        ensure
          VCR.turn_on!
          WebMock.disable_net_connect!
        end
      end

      it "should return true" do
        VCR.use_cassette('make locale default') do
          subject.make_locale_default("fr").should be_true
        end
      end
    end
  end

  describe "#download_translations_for_locale" do
    it "should raise an exception if the name is blank" do
      lambda {
        subject.download_translations_for_locale("", "yml")
      }.should raise_error "You must specify a name"
    end

    it "should raise an exception if the format is blank" do
      lambda {
        subject.download_translations_for_locale("de", "")
      }.should raise_error "You must specify a format"
    end

    context "locale does not exists" do
      it "should raise an error" do
        VCR.use_cassette('download translations for unexistant locale') do
          lambda {
            subject.download_translations_for_locale("does_not_exist", "yml")
          }.should raise_error "Translations does_not_exist could not be downloaded"
        end
      end
    end

    context "locale exists" do
      it "should return true" do
        VCR.use_cassette('download translations') do
          subject.download_translations_for_locale("en", "yml").should include "en:"
        end
      end
    end
  end

  describe "#upload" do
    context "no tag given" do
      it "should return true" do
        VCR.use_cassette('upload locale without tags') do
          subject.upload("en.yml", "en:\n  foo: bar").should be_true
        end
      end
    end

    context "tags given" do
      it "should return true" do
        VCR.use_cassette('upload locale with tags') do
          subject.upload("en.yml", "en:\n  foo: bar", ["foo", "bar"]).should be_true
        end
      end
    end

    context "a locale given" do
      it "should return true" do
        VCR.use_cassette('upload locale with a locale') do
          subject.upload("en.yml", "en:\n  foo: bar", [], "en").should be_true
        end
      end
    end

    context "no locale given" do
      it "should return true" do
        VCR.use_cassette('upload locale without locale') do
          subject.upload("en.yml", "en:\n  foo: bar", [], nil).should be_true
        end
      end
    end
  end

  describe "#display_api_error" do
    let(:response) { stub }
    let(:error_message) { stub }

    it "should render an error message to stderr" do
      subject.stub(:api_error_message).and_return(error_message)
      $stderr.should_receive(:puts).exactly(2).times
      subject.send(:display_api_error, response)
    end
  end

  describe "#api_error_message" do
    let(:response) { stub(:body => "", :code => "999") }

    it "should include the error code" do
      subject.send(:api_error_message, response).should include "(999)"
    end

    context "body contains an error field" do
      context "error field contains error message" do
        let(:response) { stub(:body => '{"error": "Some Error"}', :code => "999") }

        it "should include the error message" do
          subject.send(:api_error_message, response).should include "Some Error"
        end
      end

      context "error field contains no error message" do
        context "message field exists" do
          let(:response) { stub(:body => '{"error": true, "message": "Some Message"}', :code => "999") }

          it "should include the error message" do
            subject.send(:api_error_message, response).should include "Some Message"
          end
        end

        context "message field does not exist" do
          let(:response) { stub(:body => '{"error": true}', :code => "999") }

          it "should include the error message" do
            subject.send(:api_error_message, response).should include "Unknown Error"
          end
        end
      end
    end

    context "body contains no error message" do
      let(:response) { stub(:code => "777", :body => "") }

      it "should include 'Unknown Error'" do
        subject.send(:api_error_message, response).should include "Unknown Error"
      end
    end
  end

  describe "#perform_api_request" do
    let(:response) { stub(:body => "Some Body", :code => 200) }
    let(:http_client) { stub(:request => response) }

    before(:each) do
      subject.stub(:http_client).and_return(http_client)
    end

    it "should return the response body/content" do
      subject.send(:perform_api_request, "/bar", :get).should == "Some Body"
    end

    context "when response is 401" do
      let(:response) { stub(:code => 401, :body => "") }

      it "should raise an unauthorized exception when response is 401" do
        lambda {
          subject.send(:perform_api_request, "/bar", :get)
        }.should raise_error Phrase::Api::Exceptions::Unauthorized
      end
    end

    context "method is get" do
      it "should perform a get request" do
        http_client.should_receive(:request).with(kind_of(Net::HTTP::Get))
        subject.send(:perform_api_request, "/bar", :get)
      end
    end

    context "method is post" do
      it "should perform a post request" do
        http_client.should_receive(:request).with(kind_of(Net::HTTP::Post))
        subject.send(:perform_api_request, "/bar", :post)
      end
    end

    context "method is invalid" do
      it "should raise an error" do
        lambda {
          subject.send(:perform_api_request, "/foo", :invalid)
        }.should raise_error "Invalid Request Method: invalid"
      end
    end

    context 'API_MAX_RETRIES is set' do
      let(:api_max_retries) { 2 }
      before(:each) { Phrase::Api::Config.stub(api_max_retries: api_max_retries) }

      it 'retries the set amount when failing and raises the exception at the end' do
        subject.should_receive(:sleep).exactly(api_max_retries).times
        http_client.should_receive(:request).exactly(api_max_retries).times.and_return(stub(code: 502).as_null_object)
        expect {
          subject.send(:perform_api_request, "/bar", :get)
        }.to raise_error(Phrase::Api::Exceptions::ServerError)
      end

      it 'does not retry when status is 401 and raises the exception' do
        http_client.should_receive(:request).exactly(:once).and_return(stub(code: 401).as_null_object)
        expect {
          subject.send(:perform_api_request, "/bar", :get)
        }.to raise_error(Phrase::Api::Exceptions::Unauthorized)
      end

      it 'does not retry when status is 200' do
        http_client.should_receive(:request).exactly :once
        subject.send(:perform_api_request, "/bar", :get)
      end

      it 'does not sleep when status is 200' do
        subject.should_not_receive(:sleep)
        subject.send(:perform_api_request, "/bar", :get)
      end

      it 'does not retry when method is post' do
        http_client.should_receive(:request).exactly(1).times.and_return(stub(code: 502).as_null_object)
        expect {
          subject.send(:perform_api_request, "/bar", :post)
        }.to raise_error(Phrase::Api::Exceptions::ServerError)
      end

      it 'does not retry when method is put' do
        http_client.should_receive(:request).exactly(1).times.and_return(stub(code: 502).as_null_object)
        expect {
          subject.send(:perform_api_request, "/bar", :put)
        }.to raise_error(Phrase::Api::Exceptions::ServerError)
      end
    end
  end

  describe "#get_request" do
    it "returns a net http get request" do
      subject.send(:get_request, "/foo").should be_a(Net::HTTP::Get)
    end

    it "should include the auth token" do
      subject.send(:get_request, "/foo").path.should include("auth_token=#{auth_token}")
    end

    it "should add given params" do
      params = {:foo => "bar", :lorem => "ipsum"}
      subject.send(:get_request, "/foo", params).path.should include("foo=bar")
      subject.send(:get_request, "/foo", params).path.should include("lorem=ipsum")
    end
  end

  describe "#post_request" do
    it "returns a net http post request" do
      subject.send(:post_request, "/foo").should be_a(Net::HTTP::Post)
    end

    it "should include the auth token" do
      subject.send(:post_request, "/foo").body.should include("auth_token=#{auth_token}")
    end

    it "should add given params" do
      params = {:foo => "bar", :lorem => "ipsum"}
      subject.send(:post_request, "/foo", params).body.should include("foo=bar")
      subject.send(:post_request, "/foo", params).body.should include("lorem=ipsum")
    end
  end

  describe "#put_request" do
    it "returns a net http put request" do
      subject.send(:put_request, "/foo").should be_a(Net::HTTP::Put)
    end

    it "should include the auth token" do
      subject.send(:put_request, "/foo").body.should include("auth_token=#{auth_token}")
    end

    it "should add given params" do
      params = {:foo => "bar", :lorem => "ipsum"}
      subject.send(:put_request, "/foo", params).body.should include("foo=bar")
      subject.send(:put_request, "/foo", params).body.should include("lorem=ipsum")
    end
  end

  describe "#api_path_for" do
    it "should include the api version" do
      subject.send(:api_path_for, "/bar").should include(Phrase::API_VERSION)
    end

    it "should include the endpoint" do
      subject.send(:api_path_for, "/bar").should include("bar")
    end
  end

  describe "#http_client" do
    it "should return an instance of net/http" do
      subject.send(:http_client).should be_a(Net::HTTP)
    end

    it "should be pointing to the correct host" do
      Phrase::Api::Config.stub(:api_host).and_return("example.com")
      subject.send(:http_client).address.should == "example.com"
    end

    it "should be pointing to the correct port" do
      Phrase::Api::Config.stub(:api_port).and_return("8888")
      subject.send(:http_client).port.should == "8888"
    end
  end

  describe "#query_for_params(params)" do
    subject { Phrase::Api::Client.new("foo").send(:query_for_params, params) }

    context "with a simple structure" do
      let(:params) { {"foo[bar]" => "baz"} }
      it { should eql("foo[bar]=baz") }
    end

    context "with an array" do
      let(:params) { {"foo[bar]" => ["baz", "fooo"]} }
      it { should eql("foo[bar][]=baz&foo[bar][]=fooo") }
    end
  end
end
