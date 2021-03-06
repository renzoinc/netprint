# -*- coding: utf-8 -*-
require "tmpdir"
require "fileutils"
require "pathname"
require 'digest/md5'

module Netprint
  class Agent
    attr_reader :userid, :password

    include FileUtils

    def initialize(userid, password)
      @userid   = userid
      @password = password
      @page = nil
    end

    def login
      @page = mechanize.get('https://www.printing.ne.jp/usr/web/NPCM0010.seam')
      form = @page.form_with(name: 'NPCM0010')
      form.field_with(name: 'NPCM0010:userIdOrMailads-txt').value = @userid
      form.field_with(name: 'NPCM0010:password-pwd').value = @password
      @page = form.submit(form.button_with(name: 'NPCM0010:login-btn'))
    end

    def upload(filename, options = {})
      raise 'not logged in' unless login?

      form = @page.form_with(name: 'NPFL0010')
      @page = form.submit(form.button_with(name: 'create-document'))

      options = Options.new(options)

      file_data = open(filename, "rb") { |f| f.read }
      file_data.force_encoding('UTF-8') # change from ASCII-8BIT

      upload_filename = File.basename(filename)

      form = @page.form_with(name: 'NPFL0020')
      form.file_uploads.first.file_name = upload_filename
      form.file_uploads.first.file_data = file_data

      options.apply(form)

      @page = form.submit(form.button_with(name: 'update-ow-btn'))

      errors = @page.search('//ul[@id="svErrMsg"]/li')

      unless errors.empty?
        raise UploadError.new(errors.first.text)
      end

      get_code
    end

    def remaining_quota
      raise 'not logged in' unless login?

      data = @page.search('section.column3-3 dl dd')
      data[3].text.chomp('KB').delete(',').to_i
    end

    # Method to delete existing print jobs. As Mechanize is not able to run JavaScript,
    # this method can only be used to delete jobs on the first page displayed (1 - 10),
    # as page switching is handled by JavaScript in Netprint
    def purge(id)
      raise 'not logged in' unless login?

      while true do
        table = @page.search('table.file-details')
        table.search('tr').each do |row|
          # The checkbox. Read 'value' to be able to set it
          row_number = row.xpath('./td[1]/input/@value')
          # The NetPrintJobId
          netprint_id = row.xpath('./td[3]').text

          next unless netprint_id == id

          submit_removal(row_number)
          break
        end
        # link = @page.link_with(text: '＞')
        # return unless link
        # @page = link.click
      end
    end

    def login?
      @page && @page.code == '200'
    end

    private

    def reload
      form = @page.form_with(name: 'NPFL0010')
      @page = form.submit(form.button_with(name: 'reload'))
    end

    def get_code
      code = nil

      loop do
        reload

        _, _, status = @page.search('//tbody/tr')[0].search('td')

        if status.text =~ /^[0-9A-Z]{8}+$/
          code = status.text
          break
        elsif status.text =~ /エラー/
          raise RegistrationError
        end

        sleep 1
      end

      code
    end

    def mechanize
      @mechanize ||= Mechanize.new
      @mechanize.ssl_version = :TLSv1
      @mechanize
    end

    def submit_removal(index)
      form = @page.form_with(name: 'NPFL0010')
      form.checkbox_with(name: 'delete-flg', value: index.to_s).check
      @page = form.submit(form.button_with(name: 'delete'))

      form = @page.form_with(name: 'NPFL0040')
      form.submit(form.button_with(name: 'delete-btn'))
    end
  end

end
