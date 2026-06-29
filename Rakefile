# frozen_string_literal: true

require "bundler/gem_tasks"

# vendor:prepare must be runnable before `bundle install` (CI runs it
# first so the path-source oga/ruby-ll forks' gitignored lexer/parser
# outputs exist before their extconf.rb runs). Guard the rspec/opal
# requires so the file loads with only `rake` + `bundler` available.
begin
  require "rspec/core/rake_task"
  RSpec::Core::RakeTask.new(:spec)
rescue LoadError
end

begin
  require "opal/rspec/rake_task"

  # Opal-compatible overrides need to be on Opal's global load path so
  # the compiler can follow `require "lutaml_model_boot"` etc.
  # moxml ships its own compat files (`lib/compat/opal/`) inside the gem;
  # we add moxml's gem dir to Opal's load path so we can reuse them.
  # moxml's lib root is also added so `require "moxml"` resolves.
  if defined?(Opal)
    Opal.append_path File.expand_path("lib/compat/opal", __dir__)

    moxml_gem_dir = Gem::Specification.find_by_name("moxml")&.gem_dir
    if moxml_gem_dir
      Opal.append_path File.join(moxml_gem_dir, "lib")
      Opal.append_path File.join(moxml_gem_dir, "lib/compat/opal")
    end

    # The Opal-compatible oga and ruby-ll forks (vendored as submodules)
    # expose pure-Ruby implementations under ext/pureruby/. Their top-level
    # lib/oga.rb and lib/ll/setup.rb conditionally require them when
    # RUBY_PLATFORM == 'opal'. Both lib/ and ext/pureruby/ must be on
    # Opal's load path so the conditional resolves correctly.
    %w[opal-oga opal-ruby-ll].each do |fork_name|
      fork_path = File.expand_path("vendor/#{fork_name}", __dir__)
      Opal.append_path File.join(fork_path, "lib")
      Opal.append_path File.join(fork_path, "ext/pureruby")
    end
  end
rescue LoadError
  # Opal not available or incompatible with current Ruby version
end

begin
  require "rubocop/rake_task"
  RuboCop::RakeTask.new
rescue LoadError
end

Dir.glob("lib/tasks/**/*.rake").each { |r| load r }

# Regenerate the ragel / ruby-ll outputs that the Opal-compatible forks
# (vendored as submodules under vendor/) gitignore. The forks ship the
# grammar sources (.rl / .rll) but not the generated .rb / .c, since
# those are large and version-controllable upstream. Both ragel and
# ruby-ll must be on PATH; the upstream ruby-ll gem is sufficient for
# generation (the fork is only needed at runtime).
namespace :vendor do
  desc "Generate ragel / ruby-ll outputs in vendored opal-oga and opal-ruby-ll"
  task :prepare do
    require "fileutils"

    oga = File.expand_path("vendor/opal-oga", __dir__)
    ruby_ll = File.expand_path("vendor/opal-ruby-ll", __dir__)

    generators = [
      # oga: ruby-ll grammar -> Ruby parser
      ["ruby-ll #{oga}/lib/oga/xml/parser.rll -o #{oga}/lib/oga/xml/parser.rb",
       "#{oga}/lib/oga/xml/parser.rb",
       "#{oga}/lib/oga/xml/parser.rll"],
      ["ruby-ll #{oga}/lib/oga/xpath/parser.rll -o #{oga}/lib/oga/xpath/parser.rb",
       "#{oga}/lib/oga/xpath/parser.rb",
       "#{oga}/lib/oga/xpath/parser.rll"],
      ["ruby-ll #{oga}/lib/oga/css/parser.rll -o #{oga}/lib/oga/css/parser.rb",
       "#{oga}/lib/oga/css/parser.rb",
       "#{oga}/lib/oga/css/parser.rll"],
      # oga: ragel Ruby lexer
      ["ragel -R -F1 #{oga}/lib/oga/xpath/lexer.rl -o #{oga}/lib/oga/xpath/lexer.rb",
       "#{oga}/lib/oga/xpath/lexer.rb",
       "#{oga}/lib/oga/xpath/lexer.rl"],
      ["ragel -R -F1 #{oga}/lib/oga/css/lexer.rl -o #{oga}/lib/oga/css/lexer.rb",
       "#{oga}/lib/oga/css/lexer.rb",
       "#{oga}/lib/oga/css/lexer.rl"],
      # oga: ragel C lexer for liboga
      ["ragel -C -I #{oga}/ext/ragel -G2 #{oga}/ext/c/lexer.rl -o #{oga}/ext/c/lexer.c",
       "#{oga}/ext/c/lexer.c",
       "#{oga}/ext/c/lexer.rl"],
      # ruby-ll: ruby-ll grammar -> Ruby parser
      ["ruby-ll #{ruby_ll}/lib/ll/parser.rll -o #{ruby_ll}/lib/ll/parser.rb --no-requires",
       "#{ruby_ll}/lib/ll/parser.rb",
       "#{ruby_ll}/lib/ll/parser.rll"],
    ]

    generators.each do |cmd, output, source|
      if File.exist?(output) && File.mtime(output) >= File.mtime(source)
        next
      end

      FileUtils.mkdir_p(File.dirname(output))
      sh cmd
    end
  end

  # Bundler does not reliably compile native extensions for path-source
  # gems. Build liboga/libll explicitly so `require "oga"` resolves.
  desc "Compile liboga / libll native extensions for vendored forks"
  task :compile do
    require "fileutils"
    require "rbconfig"

    dlext = RbConfig::CONFIG["DLEXT"]

    {
      "vendor/opal-ruby-ll" => "libll",
      "vendor/opal-oga" => "liboga",
    }.each do |fork_path, ext_name|
      abs_fork = File.expand_path(fork_path, __dir__)
      lib_bundle = File.join(abs_fork, "lib", "#{ext_name}.#{dlext}")
      ext_dir = File.join(abs_fork, "ext", "c")
      extconf = File.join(ext_dir, "extconf.rb")
      lib_dir = File.join(abs_fork, "lib")
      next if File.exist?(lib_bundle)

      Dir.chdir(ext_dir) do
        sh "ruby #{extconf}"
        sh "make"
        FileUtils.cp("#{ext_name}.#{dlext}", lib_dir)
      end
    end
  end
end

if defined?(RSpec)
  namespace :spec do
    if defined?(Opal::RSpec::RakeTask)
      desc "Run Opal (JavaScript) tests"
      Opal::RSpec::RakeTask.new(:opal) do |server, runner|
        server.append_path "lib"
        server.append_path "spec"

        runner.default_path = "spec"
        # Load order matters:
        #   rexml_compat      — moxml stdlib shim (String/Encoding/StringIO) required by Oga
        #   yaml_compat       — adds YAML.safe_load / YAML.dump on top of Opal's nodejs/yaml
        #   oga, ll/setup     — forks' Opal-aware conditionals select pure-Ruby lexer
        #   moxml_boot        — eager-loads Moxml::* (lutaml-model's copy, skips broken REXML paths in moxml 0.1.25)
        #   lutaml_model_boot — eager-loads Lutaml::* (Opal ignores autoload)
        #   spec_helper, support/opal — test infrastructure
        runner.requires = %w[rexml_compat yaml_compat
                             oga ll/setup
                             moxml_boot
                             lutaml_model_boot
                             spec_helper support/opal]
        runner.files = Dir.glob("spec/lutaml/**/opal*_spec.rb")
      end

      desc "Alias for spec:opal that also runs vendor:prepare"
      task opal: "vendor:prepare"
    end
  end
end

task default: %i[spec rubocop]
