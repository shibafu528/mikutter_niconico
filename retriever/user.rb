# -*- coding: utf-8 -*-
module Plugin::Niconico
  class User < Retriever::Model
    self.keys = [[:name, :string, true],
                 [:idname, :string],
                 [:report_type, :string],
                 [:profile_image_url, :string],
                 [:url, :string],
                ]

    memoize def perma_link
      URI.parse(url).freeze
    end

    def user
      self
    end

    def profile_image_url_large
      profile_image_url
    end

    def verified?
      false
    end

    def protected?
      false
    end
  end
end
