#!/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

require 'date'
require 'pry'
require 'scraped'
require 'scraperwiki'

# require 'open-uri/cached'
# OpenURI::Cache.cache_path = '.cache'
require 'scraped_page_archive/open-uri'

@TERMS = []

def noko_for(url)
  Nokogiri::HTML(open(url).read)
end

def date_from(str)
  return '' if str.to_s.empty?
  Date.parse(str)
end

def scrape_list(url)
  noko = noko_for(url)
  noko.css('#ctl00_ContentPlaceHolder1_dmps_mpsListId option/@value').map(&:text).each_with_index do |mpid, i|
    puts i if (i % 50).zero?
    scrape_person(url, mpid) unless mpid.empty?
  end
end

def scrape_person(base, mpid)
  url = "#{base}?MpId=#{mpid}"
  noko = noko_for(url)

  grid = noko.css('table.grid')
  mems = grid.xpath('.//tr[td]').reject { |r| r.attr('class') == 'tablefooter' }.map do |row|
    tds = row.css('td')
    data = {
      id:           mpid,
      name:         noko.css('#ctl00_ContentPlaceHolder1_dmps_mpsListId option[@selected]').text.gsub(/[[:space:]]+/, ' ').tidy,
      name_el:      @gr_names[mpid],
      constituency: tds[2].text.tidy,
      party:        tds[3].text.tidy,
      party_id:     tds[3].text.tidy.split('(').first.tidy.downcase.gsub(/\W/, ''),
      term:         term_from(tds[0].text.tidy),
      start_date:   date_from(tds[1].text.tidy),
      start_reason: tds[4].text.tidy,
      source:       url,
    }
    data[:party_id] = 'ΟΟΕΟ' if data[:party] == 'ΟΟ.ΕΟ.'
    raise "No Party ID for #{data[:party]}" if data[:party_id].to_s.empty?

    if data[:start_reason] =~ /Election/ and data[:start_date].to_s != data[:term][:start_date] and data[:term][:id].to_s != '1'
      warn "Weird start date for #{data}"
    end
    data
  end

  if mems.size > 1
    mems.sort_by { |m| m[:start_date] }[0...-1].each_with_index do |mem, i|
      nextmem = mems[i + 1]
      mem[:term][:id] == nextmem[:term][:id] or next
      mem[:end_date] = (nextmem[:start_date] - 1).to_s
    end
  end

  mems.each do |mem|
    mem[:start_date] = mem[:start_date].to_s
    mem[:term] = mem[:term][:id]
  end
  # puts mems

  ScraperWiki.save_sqlite(%i(id term party start_date), mems)
end

def term_from(text)
  match = text.tidy.match(%r{
    (\d+)([snrt][tdh])
    \s*
    \(
      (\d{2}\/\d{2}\/\d{4})
      \s*-\s*
      (\d{2}\/\d{2}\/\d{4})?
    \s*\)}x) or raise "No match for #{text}"
  data = match.captures
  id = data[0].to_i
  return @TERMS[id] if @TERMS[id]
  @TERMS[id] = {
    id:         data[0],
    name:       "#{data[0]}#{data[1]} Hellenic Parliament",
    start_date: date_from(data[2]).to_s,
    end_date:   date_from(data[3]).to_s,
  }
  ScraperWiki.save_sqlite([:id], @TERMS[id], 'terms')
  @TERMS[id]
end

grn = noko_for('http://www.hellenicparliament.gr/el/Vouleftes/Diatelesantes-Vouleftes-Apo-Ti-Metapolitefsi-Os-Simera/')
@gr_names = Hash[grn.css('#ctl00_ContentPlaceHolder1_dmps_mpsListId option').map { |o| [o.attr('value'), o.text] }]

ScraperWiki.sqliteexecute('DROP TABLE data') rescue nil
scrape_list('http://www.hellenicparliament.gr/en/Vouleftes/Diatelesantes-Vouleftes-Apo-Ti-Metapolitefsi-Os-Simera/')
