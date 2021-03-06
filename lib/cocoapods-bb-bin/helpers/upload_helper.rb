

# copy from https://github.com/CocoaPods/cocoapods-packager

require 'cocoapods-bb-bin/native/podfile'
require 'cocoapods/command/gen'
require 'cocoapods/generate'
require 'cocoapods-bb-bin/helpers/framework_builder'
require 'cocoapods-bb-bin/helpers/library_builder'
require 'cocoapods-bb-bin/helpers/sources_helper'
require 'cocoapods-bb-bin/helpers/push_spec_helper'

module CBin
  class Upload
    class Helper
      include CBin::SourcesHelper

      def initialize(spec,code_dependencies,sources, pushsourcespec = false)
        @spec = spec
        @code_dependencies = code_dependencies
        @sources = sources
        @pushsourcespec = pushsourcespec # 推送源码
      end

      def upload
        Dir.chdir(CBin::Config::Builder.instance.root_dir) do
          # 创建binary-template.podsepc
          # 上传二进制文件
          # 上传二进制 podspec
          res_zip = curl_zip
          if res_zip
            filename = spec_creator
            Pod::UI.message "上传二进制 podspec: #{filename}"
            push_helper = CBin::Push::Helper.new()
            push_helper.push_binary_repo(filename)
            # 上传源码 podspec
            if @pushsourcespec
              Pod::UI.message "上传源码 podspec: #{@spec_creator.sourceSpecFilePath}"
              push_helper.push_source_repo(@spec_creator.sourceSpecFilePath)
            end
          end
          res_zip
        end
      end

      def spec_creator
        spec_creator = CBin::SpecificationSource::Creator.new(@spec)
        @spec_creator = spec_creator
        spec_creator.create
        spec_creator.write_spec_file
        spec_creator.filename
      end

      #推送二进制
      # curl http://ci.xxx:9192/frameworks -F "name=IMYFoundation" -F "version=7.7.4.2" -F "annotate=IMYFoundation_7.7.4.2_log" -F "file=@bin_zip/bin_IMYFoundation_7.7.4.2.zip"
      def curl_zip
        # lib
        zip_file = "#{CBin::Config::Builder.instance.library_file(@spec)}.zip"
        res = File.exist?(zip_file)
        unless res
          # framework
          zip_file = CBin::Config::Builder.instance.framework_zip_file(@spec) + ".zip"
          res = File.exist?(zip_file)
        end
        unless res
          # xcframework
          zip_file = CBin::Config::Builder.instance.xcframework_zip_file(@spec) + ".zip"
          res = File.exist?(zip_file)
        end
        if res
          print <<EOF
          上传二进制文件
         curl #{CBin.config.binary_upload_url} -F "name=#{@spec.name}" -F "version=#{@spec.version}" -F "annotate=#{@spec.name}_#{@spec.version}_log" -F "file=@#{zip_file}"
EOF
          `curl #{CBin.config.binary_upload_url} -F "name=#{@spec.name}" -F "version=#{@spec.version}" -F "annotate=#{@spec.name}_#{@spec.version}_log" -F "file=@#{zip_file}"` if res
        end

        res
      end

    end
  end
end
