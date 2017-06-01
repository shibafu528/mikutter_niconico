# -*- coding: utf-8 -*-
require_relative '../entity/nicorepo_entity'

module Plugin::Niconico
  class Nicorepo < Retriever::Model
    include Retriever::Model::MessageMixin

    register :nicorepo, name: "ニコレポ"

    field.string :message, required: true
    field.has    :user, Plugin::Niconico::User, required: true
    field.time   :created
    field.string :url

    entity_class Plugin::Niconico::Entity::NicorepoEntity

    def to_show
      @to_show ||= self[:message].gsub(/&(gt|lt|quot|amp);/){|m| {'gt' => '>', 'lt' => '<', 'quot' => '"', 'amp' => '&'}[$1] }.freeze
    end

    memoize def perma_link
      URI.parse(url).freeze unless url.nil?
    end

  end
end
