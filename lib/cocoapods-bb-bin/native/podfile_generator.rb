

require 'parallel'
require 'cocoapods'
require 'cocoapods-bb-bin/native/pod_source_installer'


require 'parallel'
require 'cocoapods'

module Pod
  module Generate
    # Generates podfiles for pod specifications given a configuration.
    #
    class PodfileGenerator
      # @return [Podfile] a podfile suitable for installing the given spec
      #
      # @param  [Array<Specification>] specs
      #
      def podfile_for_specs(specs)
        generator = self
        dir = configuration.gen_dir_for_specs(specs)
        project_name = configuration.project_name_for_specs(specs)

        Pod::Podfile.new do
          project "#{project_name}.xcodeproj"
          workspace "#{project_name}.xcworkspace"

          plugin 'cocoapods-generate'

          install! 'cocoapods', generator.installation_options

          generator.podfile_plugins.each do |name, options|
            plugin(*[name, options].compact)
          end

          use_frameworks!(generator.use_frameworks_value)

          if (supported_swift_versions = generator.supported_swift_versions)
            supports_swift_versions(supported_swift_versions)
          end

          # Explicitly set sources
          generator.configuration.sources.each do |source_url|
            source(source_url)
          end

          self.defined_in_file = dir.join('CocoaPods.podfile.yaml')

          test_specs_by_spec = Hash[specs.map do |spec|
            [spec, spec.recursive_subspecs.select(&:test_specification?)]
          end]
          app_specs_by_spec = Hash[specs.map do |spec|
            app_specs = if spec.respond_to?(:app_specification?)
                          spec.recursive_subspecs.select(&:app_specification?)
                        else
                          []
                        end
            [spec, app_specs]
          end]

          # Stick all of the transitive dependencies in an abstract target.
          # This allows us to force CocoaPods to use the versions / sources / external sources
          # that we want.
          
          # 会导致多个dependencies出现， 注释by slj
          # abstract_target 'Transitive Dependencies' do
          #   pods_for_transitive_dependencies = specs.flat_map do |spec|
          #     [spec.name]
          #       .concat(test_specs_by_spec.keys.map(&:name))
          #       .concat(test_specs_by_spec.values.flatten.flat_map { |ts| ts.dependencies.flat_map(&:name) })
          #       .concat(app_specs_by_spec.keys.map(&:name))
          #       .concat(app_specs_by_spec.values.flatten.flat_map { |as| as.dependencies.flat_map(&:name) })
          #   end
          #   pods_for_transitive_dependencies.uniq!

          #   spec_names = specs.map { |s| s.root.name }.to_set
          #   dependencies = generator
          #                  .transitive_dependencies_by_pod
          #                  .values_at(*pods_for_transitive_dependencies)
          #                  .compact
          #                  .flatten(1)
          #                  .uniq
          #                  .sort_by(&:name)
          #                  .reject { |d| spec_names.include?(d.root_name) }

          #   dependencies.each do |dependency|
          #     pod_args = generator.pod_args_for_dependency(self, dependency)
          #     pod(*pod_args)
          #   end
          # end

          # Add platform-specific concrete targets that inherit the `pod` declaration for the local pod.
          spec_platform_names = specs.flat_map { |s| s.available_platforms.map(&:string_name) }.uniq.each.reject do |platform_name|
            !generator.configuration.platforms.nil? && !generator.configuration.platforms.include?(platform_name.downcase)
          end

          spec_platform_names.sort.each do |platform_name|
            target "App-#{platform_name}" do
              current_target_definition.swift_version = generator.swift_version if generator.swift_version
            end
          end

          # this block has to come _before_ inhibit_all_warnings! / use_modular_headers!,
          # and the local `pod` declaration
          # current_target_definition.instance_exec do
          #   transitive_dependencies = children.find { |c| c.name == 'Transitive Dependencies' }

          #   %w[use_modular_headers inhibit_warnings].each do |key|
          #     Pod::UI::puts "====key:#{key} value:#{value}"
          #     value = transitive_dependencies.send(:internal_hash).delete(key)
          #     next if value.blank?
          #     set_hash_value(key, value)
          #   end
          # end

          inhibit_all_warnings! if generator.inhibit_all_warnings?
          # use_modular_headers! if generator.use_modular_headers?
          # podfile 配置 use_frameworks! :linkage => :static 支持modulemap by hm 21/10/19
          # Pod::UI::puts "====use_frameworks_value:#{generator.use_frameworks_value}"
          unless generator.use_frameworks_value
            use_modular_headers! # 默认组件没有配置或者没有podfile，支持modulemap by hm 21/10/20
          end
          if generator.use_modular_headers? || generator.use_frameworks_value.to_s == '{:linkage=>:static}'
            use_modular_headers!
          end

          specs.each do |spec|
            # This is the pod declaration for the local pod,
            # it will be inherited by the concrete target definitions below
            pod_options = generator.dependency_compilation_kwargs(spec.name)

            path = spec.defined_in_file.relative_path_from(dir).to_s
            pod_options[:path] = path
            { testspecs: test_specs_by_spec[spec], appspecs: app_specs_by_spec[spec] }.each do |key, subspecs|
              pod_options[key] = subspecs.map { |s| s.name.sub(%r{^#{Regexp.escape spec.root.name}/}, '') }.sort unless subspecs.blank?
            end
            pod spec.name, **pod_options
          end

          if Pod::Config.instance.podfile
            target_definitions['Pods'].instance_exec do
              target_definition = nil
              Pod::Config.instance.podfile.target_definition_list.each do |target|
                if target.label == "Pods-#{spec.name}"
                  target_definition = target
                  break
                end
              end
              # setting modular_headers_for
              if(target_definition && target_definition.use_modular_headers_hash.values.any?)
                target_definition.use_modular_headers_hash.values.each do |f|
                  f.each { | pod_name|  self.set_use_modular_headers_for_pod(pod_name, true) }
                end
              end


              if target_definition
                value = target_definition.to_hash['dependencies']
                next if value.blank?
                #删除 本地库中的 spec.name，因为本地的./spec.name地址是错的
                value.each do |f|
                  if f.is_a?(Hash) && f.keys.first == spec.name
                    value.delete f
                    break
                  end
                end
                old_value = self.to_hash['dependencies'].first
                value << old_value unless (old_value == nil || value.include?(old_value))

                set_hash_value(%w(dependencies).first, value)

                value = target_definition.to_hash['configuration_pod_whitelist']
                next if value.blank?
                set_hash_value(%w(configuration_pod_whitelist).first, value)


              end


            end

          end

          # if generator.configuration && generator.configuration.podfile
          #   #变量本地podfile下的dependencies 写入新的验证文件中，指定依赖源
          #   generator.configuration.podfile.dependencies.each { |dependencies|
          #     #如果不存在dependencies.external_source，就不变量
          #     next unless dependencies.external_source
          #
          #     dependencies.external_source.each { |key_d, value|
          #       pod_options = generator.dependency_compilation_kwargs(dependencies.name)
          #       pod_options[key_d] = value.to_s
          #       { testspecs: test_specs, appspecs: app_specs }.each do |key, specs|
          #         pod_options[key] = specs.map { |s| s.name.sub(%r{^#{Regexp.escape spec.root.name}/}, '') }.sort unless specs.empty?
          #       end
          #       # 过滤 dependencies.name == spec.name
          #       pod(dependencies.name, **pod_options) unless dependencies.name == spec.name
          #     }
          #   }
          # end


          # Implement local-sources option to set up dependencies to podspecs in the local filesystem.
          next if generator.configuration.local_sources.empty?
          specs.each do |spec|
            generator.transitive_local_dependencies(spec, generator.configuration.local_sources).sort_by(&:first).each do |dependency, podspec_file|
              pod_options = generator.dependency_compilation_kwargs(dependency.name)
              pod_options[:path] = if podspec_file[0] == '/' # absolute path
                                     podspec_file
                                   else
                                     '../../' + podspec_file
                                   end
              pod dependency.name, **pod_options
            end
          end
        end
      end
    end
  end
end
