require 'spec_helper'

describe Phrase::Tool do
  include RSpec::Helpers

  let(:argv) { stub }

  before(:each) do
    Phrase::Tool.config.reset!
  end

  describe "commands" do
    let(:api_client) { stub }

    describe "default command" do
      it "prints usage instructions" do
        phrase ""
        out.should include "phrase init"
        out.should include "phrase push"
      end
    end

    describe "init command" do
      before(:each) do
        Phrase::Tool::Commands::Init.any_instance.stub(:api_client).and_return(api_client)
      end

      describe "config generation" do
        context "no secret is given" do
          it "displays an error message" do
            phrase_cmd "init"
            err.should include "No auth token was given"
            err.should include "Please provide the --secret=YOUR_SECRET parameter."
          end
        end

        context "a secret is given" do
          it "displays a success message" do
            phrase_cmd "init --secret=secret123"
            out.should include "Wrote secret to config file .phrase"
          end

          it "should write the secret to the config file" do
            phrase_cmd "init --secret=secret123"
            File.read('.phrase').should include "secret123"
          end
        end
      end

      describe "default locale initialization" do
        context "--default-locale is given" do
          context "locale does not exist yet" do
            before(:each) do
              api_client.stub(:create_locale).with("hu").and_return(true)
              api_client.stub(:make_locale_default).with("hu").and_return(true)
            end

            it "creates the locale" do
              phrase "init --secret=secret123 --default-locale=hu"
              out.should include "Created locale \"hu\""
            end

            it "makes the locale default" do
              phrase "init --secret=secret123 --default-locale=hu"
              out.should include "Locale \"hu\" is now the default locale"
            end
          end

          describe "locale already exists" do
            before(:each) do
              api_client.stub(:create_locale).with("hu").and_raise("Error")
              api_client.stub(:make_locale_default).with("hu").and_return(true)
            end

            it "tells the user that it could not create the locale" do
              phrase "init --secret=secret123 --default-locale=hu"
              out.should_not include "Created locale \"hu\""
            end

            it "makes the locale default" do
              phrase "init --secret=secret123 --default-locale=hu"
              out.should include "Locale \"hu\" is now the default locale"
            end
          end
        end

        context "--default-locale is not set" do
          context "en locale does not exist yet" do
            before(:each) do
              api_client.stub(:create_locale).with("en").and_return(true)
              api_client.stub(:make_locale_default).with("en").and_return(true)
            end

            it "creates the locale" do
              phrase "init --secret=secret123"
              out.should include "Created locale \"en\""
            end

            it "makes en the default locale" do
              phrase "init --secret=secret123"
              out.should include "Locale \"en\" is now the default locale"
            end
          end

          context "en already exists" do
            before(:each) do
              api_client.stub(:create_locale).with("en").and_raise("Error")
              api_client.stub(:make_locale_default).with("en").and_return(true)
            end

            it "cannot create the locale" do
              phrase "init --secret=secret123"
              out.should_not include "Created locale \"en\""
            end

            it "marks en as default" do
              phrase "init --secret=secret123"
              out.should include "Locale \"en\" is now the default locale"
            end
          end
        end
      end
    end

    describe "push command" do
      before(:each) do
        Phrase::Tool::Commands::Push.any_instance.stub(:api_client).and_return(api_client)
      end

      before(:each) do
        api_client.stub(:create_locale).and_return(true)
        api_client.stub(:make_locale_default).and_return(true)
        api_client.stub(:upload).and_return(true)
      end

      it "complains when no config present" do
        begin
          phrase "push /path/to/some.yml"
        rescue SystemExit => ex
          err.should include "No auth token present"
        end
      end

      context "when no file/dir specified" do
        context "rails default directory is not available" do
          it "displays an error message" do
            begin
              phrase "init --secret=secret123"
              phrase "push"
            rescue SystemExit => ex
              err.should include "Need either a file or directory"
              err.should include "phrase push FILE"
              err.should include "phrase push DIRECTORY"
            end
          end
        end

        context "rails default dir is available" do
          before(:each) do
            Phrase::Tool::Commands::Push.any_instance.stub(:rails_default_locale_folder_available?).and_return(true)
          end

          it "uses ./config/locales as default directory" do
            begin
              phrase "init --secret=secret123"
              phrase "push"
            rescue SystemExit
              out.should include "No file or directory specified, using ./config/locales"
            end
          end
        end
      end

      context "file is given" do
        before(:each) do
          phrase "init --secret=secret123"
        end

        context "file does not exist" do
          it "displays an error message" do
            begin
              phrase "push does_not_exist.yml"
            rescue SystemExit
              err.should include "The file does_not_exist.yml could not be found."
            end
          end
        end

        context "file exists" do
          describe "file formats" do
            before(:each) do
              api_client.stub(:upload).and_return(stub)
            end

            it "can upload .yml" do
              phrase "push spec/fixtures/formats/translations.en.yml"
              out.should include "Uploading spec/fixtures/formats/translations.en.yml"
            end

            it "can upload .po" do
              phrase "push spec/fixtures/formats/translations.en.po"
              out.should include "Uploading spec/fixtures/formats/translations.en.po"
            end

            it "can upload .resx" do
              phrase "push spec/fixtures/formats/translations.en.resx --format=resx"
              out.should include "Uploading spec/fixtures/formats/translations.en.resx"
            end

            it "can upload .resx for windows phone" do
              phrase "push spec/fixtures/formats/translations.en.resx --format=resx_windowsphone"
              out.should include "Uploading spec/fixtures/formats/translations.en.resx"
            end

            it "can upload .xml" do
              phrase "push spec/fixtures/formats/translations.en.xml"
              out.should include "Uploading spec/fixtures/formats/translations.en.xml"
            end

            it "can upload .strings" do
              phrase "push spec/fixtures/formats/translations.en.strings"
              out.should include "Uploading spec/fixtures/formats/translations.en.strings"
            end

            it "can upload .json" do
              phrase "push spec/fixtures/formats/translations.en.json"
              out.should include "Uploading spec/fixtures/formats/translations.en.json"
            end

            it "can upload .ts" do
              phrase "push spec/fixtures/formats/translations.en.ts"
              out.should include "Uploading spec/fixtures/formats/translations.en.ts"
            end

            it "can upload .qph" do
              phrase "push spec/fixtures/formats/translations.en.qph"
              out.should include "Uploading spec/fixtures/formats/translations.en.qph"
            end

            it "can upload .ini" do
              phrase "push spec/fixtures/formats/translations.en.ini"
              out.should include "Uploading spec/fixtures/formats/translations.en.ini"
            end

            it "can upload .plist" do
              phrase "push spec/fixtures/formats/translations.en.plist"
              out.should include "Uploading spec/fixtures/formats/translations.en.plist"
            end

            it "can upload .properties" do
              phrase "push spec/fixtures/formats/translations.en.properties"
              out.should include "Uploading spec/fixtures/formats/translations.en.properties"
            end

            it "can upload .xlf" do
              phrase "push spec/fixtures/formats/translations.en.xlf"
              out.should include "Uploading spec/fixtures/formats/translations.en.xlf"
            end
          end

          context "multiple files are given" do
            before(:each) do
              api_client.should_receive(:upload)
            end

            it "uploads all of them" do
              phrase "push spec/fixtures/formats/translations.en.yml spec/fixtures/formats/translations.en.ini"
              out.should include "Uploading spec/fixtures/formats/translations.en.yml"
              out.should include "Uploading spec/fixtures/formats/translations.en.ini"
            end
          end

          context "tag(s) given" do
            it "should use the tag in the upload call" do
              api_client.should_receive(:upload).with(kind_of(String), kind_of(String), ["foobar"], nil, nil, false, false)
              phrase "push spec/fixtures/yml/nice.en.yml --tags=foobar"
            end

            it "should mention the tag in the output" do
              phrase "push spec/fixtures/yml/nice.en.yml --tags=foo,bar"
              out.should include "(tagged: foo, bar)"
            end

            context "tag name is invalid" do
              it "should not perform the upload" do
                begin
                  phrase "push spec/fixtures/yml/nice.en.yml --tags=tes$"
                rescue SystemExit => ex
                  err.should include "Invalid tags"
                end
              end
            end
          end
        end

        context "file extension is not supported" do
          it "does not upload the file" do
            phrase "push spec/fixtures/edge/wrongext.doc"
            api_client.should_not_receive(:upload)
          end

          it "should display an error message" do
            phrase "push spec/fixtures/edge/wrongext.doc"
            err.should match "Notice: Could not upload"
          end
        end
      end

      context "directory is given" do
        before(:each) do
          phrase "init --secret=my_secret"
        end

        it "uploads every file from the directoy" do
          phrase "push spec/fixtures/yml"
          out.should match %r=Uploading.*spec/fixtures/yml/nice.de.yml=im
          out.should match %r=Uploading.*spec/fixtures/yml/nice.en.yml=im
        end

        it "skips files with unsupported file extensions but uploads correct files" do
          phrase "push spec/fixtures/mixed"
          err.should match %r=(Notice: Could not upload .*spec/fixtures/mixed/wrong.yml.rb)=
          out.should match %r=(Uploading .*spec/fixtures/mixed/nice.yml)=im
        end

        context "without -R/--recursive" do
          it "should only push the files in the given directory (without subfolders)" do
            phrase "push spec/fixtures/mixed"
            out.should_not match %r=(subitem.yml)=im
          end
        end

        context "with -R/--recursive" do
          it "should push all files recursively" do
            phrase "push -R spec/fixtures/mixed"
            out.should match %r=(subitem.yml)=im
          end
        end
      end
    end

    describe "pull command" do
      before(:each) do
        Phrase::Tool::Commands::Pull.any_instance.stub(:api_client).and_return(api_client)
      end

      before(:each) do
        ::FileUtils.rm_rf("ru.lproj")
        ::FileUtils.rm_rf("res")
        ::FileUtils.rm_rf("phrase/locales/")
        api_client.stub(:download_translations_for_locale).with("pl", kind_of(String), nil, nil, nil).and_return("content for pl")
        api_client.stub(:download_translations_for_locale).with("ru", kind_of(String), nil, nil, nil).and_return("content for ru")
        api_client.stub(:download_translations_for_locale).with("de", kind_of(String), nil, nil, nil).and_return("content for de")
        api_client.stub(:download_translations_for_locale).with("cn", kind_of(String), nil, nil, nil).and_raise("Error")
      end

      after(:each) do
        ::FileUtils.rm_rf("ru.lproj")
        ::FileUtils.rm_rf("res")
      end

      context "when no auth token is present" do
        it "raises an error" do
          begin
            phrase "pull fr"
          rescue SystemExit
            err.should include "No auth token present"
          end
        end
      end

      context "auth token is present" do
        let(:list_of_locales) { [
          Phrase::Tool::Locale.new({name: "de"}),
          Phrase::Tool::Locale.new({name: "ru"}),
          Phrase::Tool::Locale.new({name: "pl"})
        ] }

        before(:each) do
          phrase "init --secret=my_secret"
          Phrase::Tool::Locale.stub(:all).and_return(list_of_locales)
        end

        context "locale is invalid" do
          it "should render an error" do
            begin
              phrase "pull cn"
              File.exists?("phrase/locales/phrase.cn.yml").should be_false
            rescue SystemExit
              err.should include "Error"
            end
          end
        end

        context "a locale is given" do
          describe "format handling" do
            context "no format is specified" do
              it "should fetch translations for the locale in yml format and store it" do
                phrase "pull ru"
                File.read("phrase/locales/phrase.ru.yml").should == "content for ru"
              end
            end

            context "an invalid format is specified" do
              it "should not fetch translations" do
                begin
                  phrase "pull ru --format=doc"
                rescue SystemExit
                  err.should include "Invalid format"
                  File.exists?("phrase/locales/phrase.ru.doc").should be_false
                end
              end
            end

            context "valid format is specified" do
              it "should store in po format" do
                phrase "pull ru --format=gettext"
                File.read("locales/ru/phrase.po").should == "content for ru"
              end

              it "should store in yml format" do
                phrase "pull ru --format=yml"
                File.read("phrase/locales/phrase.ru.yml").should == "content for ru"
              end

              it "should store in yml_symfony format" do
                phrase "pull ru --format=yml_symfony"
                File.read("phrase/locales/phrase.ru.yml").should == "content for ru"
              end

              it "should store in xml format" do
                phrase "pull ru --format=xml"
                File.read("res/values-ru/strings.xml").should == "content for ru"
              end

              it "should store in strings format" do
                phrase "pull ru --format=strings"
                File.read("ru.lproj/Localizable.strings").should == "content for ru"
              end

              it "should store in xlf format" do
                phrase "pull ru --format=xlf"
                File.read("phrase/locales/phrase.ru.xlf").should == "content for ru"
              end

              it "should store in qph format" do
                phrase "pull ru --format=qph"
                File.read("phrase/locales/phrase.ru.qph").should == "content for ru"
              end

              it "should store in ts format" do
                phrase "pull ru --format=ts"
                File.read("phrase/locales/phrase.ru.ts").should == "content for ru"
              end

              it "should store in json format" do
                phrase "pull ru --format=json"
                File.read("phrase/locales/phrase.ru.json").should == "content for ru"
              end

              it "should store in resx format" do
                phrase "pull ru --format=resx"
                File.read("phrase/locales/phrase.ru.resx").should == "content for ru"
              end

              it "should store in ini format" do
                phrase "pull ru --format=ini"
                File.read("phrase/locales/phrase.ru.ini").should == "content for ru"
              end

              it "should store in properties format" do
                phrase "pull ru --format=properties"
                File.read("phrase/locales/phrase.ru.properties").should == "content for ru"
              end

              it "should store in properties xml format" do
                phrase "pull ru --format=properties_xml"
                File.read("phrase/locales/phrase.ru.xml").should == "content for ru"
              end

              it "should store in plist format" do
                phrase "pull ru --format=plist"
                File.read("phrase/locales/phrase.ru.plist").should == "content for ru"
              end
            end
          end

          context "a target folder is specified" do
            before(:each) do
              ::FileUtils.rm_rf("inexistant")
            end

            after(:each) do
              ::FileUtils.rm_rf("inexistant")
            end

            it "should fetch translations and store it in the given directory" do
              phrase "pull ru --target=phrase/"
              File.read("phrase/phrase.ru.yml").should == "content for ru"
            end

            context "target folder does not exist" do
              before(:each) do
                phrase "pull ru --target=inexistant/folder"
              end

              it "should create the folder and save the content" do
                File.exists?("inexistant/folder/phrase.ru.yml").should be_true
              end
            end
          end
        end

        context "no locale is given" do
          before(:each) do
            phrase "init --secret=my_secret"
          end

          it "should download each translation file and store it" do
            phrase "pull"
            File.read("phrase/locales/phrase.de.yml").should == "content for de"
            File.read("phrase/locales/phrase.pl.yml").should == "content for pl"
          end

          context "a target folder is specified" do
            before(:each) do
              ::FileUtils.rm_rf("phrase/phrase.de.yml")
              ::FileUtils.rm_rf("phrase/phrase.pl.yml")
            end

            after(:each) do
              ::FileUtils.rm_rf("phrase/phrase.de.yml")
              ::FileUtils.rm_rf("phrase/phrase.pl.yml")
            end

            it "should fetch translations and store it in the given directory" do
              phrase "pull --target=phrase/"
              File.read("phrase/phrase.de.yml").should == "content for de"
              File.read("phrase/phrase.pl.yml").should == "content for pl"
            end

            context "target folder does not exist" do
              before(:each) do
                ::FileUtils.rm_rf("inexistant")
                phrase "pull --target=inexistant/folder"
              end

              after(:each) do
                ::FileUtils.rm_rf("inexistant")
              end

              it "should not save the content" do
                File.exists?("inexistant/folder/phrase.de.yml").should be_true
                File.exists?("inexistant/folder/phrase.pl.yml").should be_true
              end
            end
          end
        end
      end
    end
  end

  describe '.instance' do
    it 'is always the same' do
      config = Phrase::Tool.config
      Phrase::Tool.config.object_id.should == config.object_id
    end
  end

end
