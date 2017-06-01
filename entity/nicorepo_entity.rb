# -*- coding: utf-8 -*-

module Plugin::Niconico
  module Entity
    class NicorepoEntity < Retriever::Entity::URLEntity

      def initialize(*rest)
        super(*rest)
        segments = Set.new(@generate_value)
        segments << {
          message: message,
          from: :nicorepo,
          slug: :urls,
          range: Range.new(0, message[:user][:name].length, true),
          face: message[:user][:name],
          url: message[:user][:url],
          open: message[:user][:url]
        }
        @generate_value = segments.sort_by{ |r| r[:range].first }.freeze
      end
    end
  end
end
