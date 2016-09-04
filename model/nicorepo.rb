# -*- coding: utf-8 -*-
module Plugin::Niconico
  class Nicorepo < Retriever::Model
    include Retriever::Model::MessageMixin

    register :nicorepo, name: "ニコレポ"

    field.string :message, required: true
    field.has    :user, Plugin::Niconico::User, required: true
    field.time   :created
    field.string :url, required: true

    entity_class Retriever::Entity::URLEntity

    def to_show
      @to_show ||= self[:message].gsub(/&(gt|lt|quot|amp);/){|m| {'gt' => '>', 'lt' => '<', 'quot' => '"', 'amp' => '&'}[$1] }.freeze
    end

    memoize def perma_link
      URI.parse(url).freeze
    end

  end
end
