require "spec_helper"

describe Phrase::Tool::Commands::Pull do
  let(:format) { "yml" }
  let(:target) { "./phrase/locales" }
  let(:args) { [] }
  let(:options) { Phrase::Tool::Options.new(args, "pull") }
  let(:api_client) { stub }
  let(:config) { stub(secret: "secr3t", format: nil) }

  let(:polish_locale) { Phrase::Tool::Locale.new(name: "pl") }
  let(:russian_locale) { Phrase::Tool::Locale.new(name: "ru") }

  before(:each) do
    Phrase::Tool::Commands::Pull.any_instance.stub(:config).and_return(config)
    Phrase::Tool::Commands::Pull.any_instance.stub(:print_message)
    Phrase::Tool::Commands::Pull.any_instance.stub(:print_error)
  end

  subject { Phrase::Tool::Commands::Pull.new(options, args) }

  context "no auth token is given" do
    let(:config) { stub(secret: nil) }

    it "should exit when no secret key given" do
      lambda {
        Phrase::Tool::Commands::Pull.new(options, args)
      }.should raise_error {|error|
        error.should be_a(SystemExit)
        error.status.should eq(1)
      }
    end
  end

  describe "#execute!" do
    before(:each) do
      subject.stub(:fetch_locales).and_return([russian_locale, polish_locale])
    end

    context "when a locale was given" do
      let(:args) { ["", "ru", nil] }

      it "should fetch the given locale" do
        subject.should_receive(:print_message).with(/downloading ru.../i)
        subject.should_receive(:fetch_translations_for_locale).with(kind_of(Phrase::Tool::Locale), "yml", nil, nil, nil)
        subject.execute!
      end

      context "when the locale does not exist" do
        let(:args) { ["", "invalidlocale"] }

        it "should display an error" do
          subject.should_receive(:print_error).with(/locale invalidlocale does not exist/i)
          subject.should_not_receive(:fetch_translations_for_locale)
          subject.execute!
        end
      end
    end

    context "when no locale was given" do
      let(:args) { [] }

      it "should fetch all locales" do
        subject.should_receive(:print_message).with(/downloading ru.../i)
        subject.should_receive(:print_message).with(/downloading pl.../i)
        subject.should_receive(:fetch_translations_for_locale).with(russian_locale, "yml", nil, nil, nil)
        subject.should_receive(:fetch_translations_for_locale).with(polish_locale, "yml", nil, nil, nil)
        subject.execute!
      end
    end
  end

  describe "#fetch_translations_for_locale" do
    let(:api_client) { stub(:download_translations_for_locale => "foo:\n  bar: content") }

    before(:each) do
      subject.stub(:print_error)
      subject.stub(:print_server_error)
      subject.stub(:print_message)
      subject.stub(:api_client).and_return(api_client)
      subject.stub(:store_translations_file)
    end

    it "fetches translations for a locale" do
      api_client.should_receive(:download_translations_for_locale).with("pl", "yml", nil, nil, nil)
      subject.send(:fetch_translations_for_locale, polish_locale, "yml")
    end

    context "translations can be downloaded" do
      it "should save the content to a file" do
        subject.should_receive(:store_content_in_locale_file).with(polish_locale, "foo:\n  bar: content")
        subject.send(:fetch_translations_for_locale, polish_locale, "yml")
      end
    end

    context "translations cannot be downloaded" do
      before(:each) do
        api_client.stub(:download_translations_for_locale).and_raise("Error")
        subject.stub(:print_server_error)
      end

      it "should display failure message" do
        subject.should_receive(:print_error).with("Failed")
        subject.send(:fetch_translations_for_locale, polish_locale, "yml")
      end

      it "should render the server error" do
        subject.should_receive(:print_server_error)
        subject.send(:fetch_translations_for_locale, polish_locale, "yml")
      end
    end
  end

  describe "#store_content_in_locale_file(locale_name, content)" do
    before(:each) do
      %w(yml txt).each { |format| File.delete("phrase/locales/phrase.foo.#{format}") if File.exists?("phrase/locales/phrase.foo.#{format}") }
    end

    after(:each) do
      %w(yml txt).each { |format| File.delete("phrase/locales/phrase.foo.#{format}") if File.exists?("phrase/locales/phrase.foo.#{format}") }
    end

    context "file does not exist" do
      it "should store content to a file" do
        subject.send(:store_content_in_locale_file, polish_locale, "mycontent")
        File.read("phrase/locales/phrase.pl.yml").should == "mycontent"
      end
    end

    context "file exists" do
      before(:each) do
        FileUtils.mkpath("phrase/locales/")
        File.open("phrase/locales/phrase.pl.yml", "w") do |file|
          file.write("hello")
        end
      end

      it "should override the file" do
        subject.send(:store_content_in_locale_file, polish_locale, "mycontent")
        File.read("phrase/locales/phrase.pl.yml").should == "mycontent"
      end
    end
  end

  describe "#fetch_locales" do
    before(:each) do
      subject.stub(:print_error)
      subject.stub(:print_server_error)
      subject.stub(:print_message)
      Phrase::Tool::Locale.stub(:api_client).and_return(api_client)
    end

    let(:de_locale) { Phrase::Tool::Locale.new(id: 43, name: "de", code: "de-DE", is_default: true) }
    let(:en_locale) { Phrase::Tool::Locale.new(id: 44, name: "en", code: nil, is_default: false) }

    context "locales could be fetched" do
      before(:each) do
        api_client.stub(:fetch_locales).and_return([{id: 43, name: "de", code: "de-DE", is_default: true}, {id: 44, name: "en", code: nil, is_default: false}])
      end

      it "should return the locales" do
        subject.send(:fetch_locales).should include de_locale
        subject.send(:fetch_locales).should include en_locale
      end
    end

    context "locales could not be fetched" do
      before(:each) do
        api_client.stub(:fetch_locales).and_raise("Some server error")
      end

      it "should terminate the script" do
        lambda {
          subject.send(:fetch_locales)
        }.should raise_error {|error|
         error.should be_a(SystemExit)
         error.status.should eq(1)
        }
      end

      it "should display an error message" do
        subject.stub(:exit_command)
        subject.should_receive(:print_error).with(/could not fetch locales from server/i)
        subject.send(:fetch_locales)
      end
    end
  end

  describe "#format_valid?" do
    subject { Phrase::Tool::Commands::Pull.new(options, args).send(:format_valid?, format) }

    context "format is in list of valid formats" do
      let(:format) { "yml" }
      it { should be_true }
    end

    context "format is not in list of valid formats" do
      let(:format) { "foo" }
      it { should be_false }
    end
  end
end
