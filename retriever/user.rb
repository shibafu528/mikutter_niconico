# -*- coding: utf-8 -*-
module Plugin::Niconico
  class User < Retriever::Model
    include Retriever::Model::UserMixin
    self.keys = [[:name, :string, true],
                 [:idname, :string],
                 [:report_type, :string],
                 [:profile_image_url, :string],
                 [:url, :string],
                ]

    memoize def perma_link
      URI.parse(url).freeze
    end

  end
end
