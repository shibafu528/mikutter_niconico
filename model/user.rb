# -*- coding: utf-8 -*-
module Plugin::Niconico
  class User < Retriever::Model
    include Retriever::Model::UserMixin

    field.string :name, required: true
    field.string :idname
    field.string :report_type
    field.string :profile_image_url
    field.string :url

    memoize def perma_link
      URI.parse(url).freeze
    end

  end
end
