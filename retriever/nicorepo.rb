# -*- coding: utf-8 -*-
module Plugin::Niconico
  class Nicorepo < Retriever::Model
    include Retriever::Model::MessageMixin

    register :nicorepo, name: "ニコレポ"

    self.keys = [[:message, :string, true],
                 [:user, Plugin::Niconico::User, true],
                 [:created, :time],
                 [:url, :string, true]
                ]
    def links
      @entity ||= Message::Entity.new(self)
    end

    def to_show
      @to_show ||= self[:message].gsub(/&(gt|lt|quot|amp);/){|m| {'gt' => '>', 'lt' => '<', 'quot' => '"', 'amp' => '&'}[$1] }.freeze
    end

    memoize def perma_link
      URI.parse(url).freeze
    end

  end
end
