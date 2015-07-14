#!/bin/env ruby
# encoding: utf-8

require 'scraperwiki'
require 'nokogiri'
require 'open-uri'
require 'cgi'
require 'json'
require 'date'
require 'colorize'

require 'pry'
require 'open-uri/cached'
OpenURI::Cache.cache_path = '.cache'

@TERMS = []

def noko_for(url)
  Nokogiri::HTML(open(url).read) 
end

def date_from(str)
  return if str.to_s.empty?
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
      id: mpid,
      name: noko.css('#ctl00_ContentPlaceHolder1_dmps_mpsListId option[@selected]').text.gsub(/[[:space:]]+/,' ').strip,
      constituency: tds[2].text.strip,
      party: tds[3].text.strip,
      party_id: tds[3].text.strip.split('(').first.strip.downcase.gsub(/\W/,''),
      term: term_from(tds[0].text.strip),
      start_date: date_from(tds[1].text.strip),
      start_reason: tds[4].text.strip,
      source: url,
    }
    if data[:start_reason] =~ /Election/ and data[:start_date].to_s != data[:term][:start_date] and data[:term][:id].to_s != '1'
      raise "Weird start date for #{data}" 
    end
    data
  end
  
  if mems.size > 1
    mems.sort_by { |m| m[:start_date] }[0...-1].each_with_index do |mem, i|
      nextmem = mems[i+1] 
      mem[:term][:id] == nextmem[:term][:id] or next
      mem[:end_date] = (nextmem[:start_date] - 1).to_s
    end
  end

  mems.each do |mem|
    mem[:start_date] = mem[:start_date].to_s
    mem[:term] = mem[:term][:id]
    # puts mem
    ScraperWiki.save_sqlite([:id, :term], mem)
  end
end

def term_from(text)
  match = text.strip.match(%r{
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
    id: data[0],
    name: "#{data[0]}#{data[1]} Hellenic Parliament",
    start_date: date_from(data[2]).to_s,
    end_date: date_from(data[3]).to_s,
  }
  ScraperWiki.save_sqlite([:id], @TERMS[id], 'terms')
  return @TERMS[id]
end

scrape_list('http://www.hellenicparliament.gr/en/Vouleftes/Diatelesantes-Vouleftes-Apo-Ti-Metapolitefsi-Os-Simera/')
