require "spring/watcher"
require "spring/watcher/abstract"

require "listen"
require "listen/version"

if defined?(Celluloid)
  # fork() doesn't preserve threads, so a clean
  # Celluloid shutdown isn't possible, but we can
  # reduce the 10 second timeout

  # There's a patch for Celluloid to avoid this (search for 'fork' in Celluloid
  # issues)
  Celluloid.shutdown_timeout = 2
end

module Spring
  module Watcher
    class Listen < Abstract
      Spring.watch_method = self

      attr_reader :listener, :poller

      def start
        return if @listener || @poller

        root_files, @files = files.partition { |f| File.expand_path("#{f}/..") == root }
        root_directories, @directories = directories.partition { |d| d == root }

        unless base_directories.empty?
          @listener = ::Listen.to(*base_directories, latency: latency, &method(:changed))
          @listener.start
        end

        if !root_files.empty? || !root_directories.empty?
          start_polling_watcher(root_files, root_directories)
        end
      end

      def stop
        if @listener
          @listener.stop
          @listener = nil
        end

        if @poller
          @poller.stop
          @poller = nil
        end
      end

      def subjects_changed
        return unless @listener
        return unless @listener.respond_to?(:directories)
        return unless @listener.directories.sort != base_directories.sort
        restart
      end

      def watching?(file)
        files.include?(file) || file.start_with?(*directories)
      end

      def changed(modified, added, removed)
        debug { "changed: #{modified}, #{added}, #{removed}" }
        synchronize do
          if (modified + added + removed).any? { |f| watching? f }
            mark_stale
          end
        end
      end

      def base_directories
        (files.map { |f| File.expand_path("#{f}/..") } + directories.to_a).uniq.map { |path| Pathname.new(path) }
      end

      def start_polling_watcher(files, directories)
        @poller = Spring::Watcher::Polling.new(root, latency)
        @poller.add(files, directories)
        @poller.instance_variable_set(:@listeners, @listeners)
        @poller.instance_variable_set(:@on_debug, @on_debug)
        @poller.start
      end
    end
  end
end
