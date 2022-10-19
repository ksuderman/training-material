require 'jekyll'
require './_plugins/gtn.rb'

module Jekyll
  class Boxify < Jekyll::Generator
    def initialize(config)
      @config = config['boxify'] ||= {}
    end

    def generate(site)
      puts "[GTN/Boxify]"
      site.pages.each { |page| boxify page,site }
      site.posts.docs.each { |post| boxify post, site }
    end

    def boxify(page, site)
      if page.content.nil?
        return
      end

      if page['lang']
        lang = page['lang']
      else
        lang = "en"
      end

      # Interim solution, fancier box titles
      page.content = page.content.gsub(/<(#{Gtn::Boxify.box_classes})-title>(.*)<\/\s*\1-title>/) {
        box_type = $1
        title = $2
        _, box = Gtn::Boxify.generate_title(box_type, title, lang, page.path)

        # Ugly hack needed, as this runs later in the pipeline than json generation.
        box.gsub!(/\\&quot/, '&quot')
        box.gsub!(/([^\\])"/, '\1\\"')

        box
      }

      # Long term solution, proper new boxes
      page.content = page.content.gsub(/<(#{Gtn::Boxify.box_classes})>/) {
        box_type = $1
        box = Gtn::Boxify.generate_box(box_type, nil, lang, page.path)
        box
      }

      page.content = page.content.gsub(/<(#{Gtn::Boxify.box_classes}) title="([^"]*)">/) {
        box_type = $1
        title = $2
        box = Gtn::Boxify.generate_box(box_type, title, lang, page.path)
        box
      }

      page.content = page.content.gsub(/<\/\s*(#{Gtn::Boxify::box_classes})\s*>/) {
        box_type = $1
        "\n</div></div><!--#{box_type}-->"
      }
    end
  end
end
