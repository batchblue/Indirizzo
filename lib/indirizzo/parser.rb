require 'indirizzo/match'
require 'indirizzo/helper'
require 'indirizzo/street'
require 'indirizzo/constants'

module Indirizzo
  class Parser
    def initialize(text, options={})
      @text = text
      @options = options
    end

    def parse
      text = @text.clone

      @zip, @plus4, zip_index, zip_end_index = extract_zip_from_text(text)

      @country = @text[zip_end_index+1..-1].sub(/^\s*,\s*/, '').strip
      @country = nil if @country == text

      @state, @full_state, @city, state_index = extract_state_from_text(text)

      @prenum, @number, @sufnum, number_end_index = process_number(text)

      # FIXME: special case: Name_Abbr gets a bit aggressive
      # about replacing St with Saint. exceptional case:
      # Sault Ste. Marie

      # FIXME: PO Box should geocode to ZIP
      street_search_end_index = [state_index,zip_index,text.length].reject(&:nil?).min-1
      @street = text[number_end_index+1..street_search_end_index].scan(Match[:street]).map { |s| s and s.strip }

      @street = Street.expand(@street) if @options[:expand_streets]
      # SPECIAL CASE: 1600 Pennsylvania 20050
      @street << @full_state if @street.empty? and @state.downcase != @full_state.downcase

      street_end_index = @street.map { |s| text.rindex(s) }.reject(&:nil?).min||0

      process_city(text, street_end_index, street_search_end_index)

      return @city, @street, @number, @prenum, @sufnum, @full_state, @state, @zip, @plus4, @country
    end

    private

    def extract_zip_from_text(text)
      zip = text.scan(Match[:zip]).last
      if zip
        last_match = $&
          zip_index = text.rindex(last_match)
        zip_end_index = zip_index + last_match.length - 1
        zip, plus4 = zip.map {|s| s and s.strip }
      else
        zip = plus4 = ""
        zip_index = text.length
        zip_end_index = -1
      end
      return zip, plus4, zip_index, zip_end_index
    end

    def extract_state_from_text(text)
      state = text.scan(Match[:state]).last
      if state
        last_match = $&
          state_index = text.rindex(last_match)
        idx = text.rindex(last_match)
        full_state = state[0].strip # special case: New York
        state = State[full_state]
        city = "Washington" if state == "DC" && text[idx...idx+last_match.length] =~ /washington\s+d\.?c\.?/i
      else
        full_state = ""
        state = ""
      end
      return state, full_state, city, state_index
    end

    def process_city(text, street_end_index, street_search_end_index)
      if @city.nil? || @city.empty?
        @city = text[street_end_index..street_search_end_index+1].scan(Match[:city])
        if !@city.empty?
          #@city = [@city[-1].strip]
          @city = [@city.last.strip]
          add = @city.map {|item| item.gsub(Name_Abbr.regexp) {|m| Name_Abbr[m]}}
          @city |= add
          @city.uniq! {|s| s.downcase}
        else
          @city = []
        end

        # SPECIAL CASE: no city, but a state with the same name. e.g. "New York"
        @city << @full_state if @state.downcase != @full_state.downcase
      end
    end

    def process_number(text)
      number = text.scan(Match[:number]).first
      # FIXME: 230 Fish And Game Rd, Hudson NY 12534
      if number # and not intersection?
        last_match = $&
          number_index = text.index(last_match)
        number_end_index = number_index + last_match.length - 1
        prenum, number, sufnum = number.map {|s| s and s.strip}
      else
        number_end_index = -1
        prenum = number = sufnum = ""
      end
      return prenum, number, sufnum, number_end_index
    end
  end
end
