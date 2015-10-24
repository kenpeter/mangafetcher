#!/usr/bin/env node_modules/coffee-script/bin/coffee

fs        = require('fs')
request   = require('request') # do stuff with http
program   = require('commander')
async     = require('async') # Better async 
_         = require('lodash') # manu utilies
exec      = require('child_process').exec
moment    = require('moment') # It is for the date
cheerio   = require('cheerio')
clc       = require('cli-color') # With some nice color for terminal
mangaUrls = require('./database')

program
  .version('0.0.1')
  .usage('-m [manga ex. bleach] -v [volume ex. 30] -e [episode ex. 268]')
  .option('-m, --manga <value>', 'Specify manga, view manga list on https://github.com/phatograph/mangafetcher#currently-supported-manga')
  .option('-v, --volume <n>', 'Specify volume')
  .option('-e, --episode <a>..<b>', 'Specify episode', (val) -> val.split('..').map(Number))
  .option('-p, --pages [items]', 'Specify pages (optional) e.g. -p 2,4,5', (val) -> val.split(','))
  .option('-l, --list', 'List mode')
  .option('-x, --eplist', 'Episode List mode')
  .option('-r, --rerender <value>', 'Rerender mode (for mangahere)')
  .option('-w, --ver <value>', 'Specify version')
  .parse(process.argv)

##############################################################################
# Image Downloading Functions
##############################################################################

# Shared variables
pages      = {}
pageAmount = {}
host       = undefined  
# It becomes void 0 always return undefined in pure javascript, because you can do var undefined = 'something'
# undefined is not reserved.
host       = undefined

padding = (value, length) ->
  # Very simple, ('0' for i in [0...length])
  # The i will be assigned with i = ref[index]
  # result = [], result.push('0')
  #
  # Input: value = 1, length = 2
  # Output will be "in steps"
  # 1. ['0', '0'] (after the loop)
  # 2. 001 (after the join)
  # 3. '001'.slice(-2), grab the 2 elements from right
  tmp_1 = ('0' for i in [0...length]).join('');
  tmp_2 = tmp_1 + value;
  tmp_3 = String(tmp_2);
  tmp_4 = tmp_3.slice(length * -1)  

  #String(('0' for i in [0...length]).join('') + value).slice(length * -1)
  tmp_4

createFolder = (folderPath) ->
  for path in folderPath.split '/'
    initPath = "#{initPath || '.'}/#{path}" # So you can add more path head, #{path}. Every time it is building a new path
    # You have to realize that initPath is incremental.
    fs.mkdirSync(initPath) unless fs.existsSync(initPath)

imageDownload = (imgUri, i, paddedVol, paddedEp, ep) ->
  request.head uri: imgUri, followRedirect: false, (err2, res2, body2) ->

    if err2 or res2.statusCode isnt 200
      console.log clc.red "Oops, something went wrong. Error: #{err2}"
      return false
    if res2.headers['content-type'] is 'image/jpeg'
      folderPath  = "manga/#{program.manga}/#{program.manga}-#{paddedVol}-#{paddedEp}" # manga/one_piece/one_piece-001-001
      folderPath += "-#{program.pages}" if host is 'http://mangapark.com/' and program.pages # folderPath === manga/one_piece/one_piece-001-001
      fileName    = "#{padding(i, 3)}.jpg" # '008.jpg', so i is page num, and it is backward
      filePath    = "./#{folderPath}/#{fileName}" # ./manga/one_piece/one_piece-001-001/008.jpg

      createFolder(folderPath)
      request(uri: imgUri, timeout: 120 * 1000)
        .pipe fs.createWriteStream(filePath) # Get the request result, then stream to file
        .on 'finish', ->

          # test
          debugger;

          pages[ep].splice(pages[ep].indexOf(i), 1)

          # Since iOS seems to sort images by created date, this should do the trick.
          # Also rounds this by 60 (minutes)
          exec("touch -t #{moment().format('YYYYMMDD')}#{padding(~~(i / 60), 2)}#{padding(i % 60, 2)} #{filePath}")

          if pages[ep].length is 0
            console.log clc.green "\nDone ##{ep}!"
          else if pages[ep].length > 3
            if (pageAmount[ep] - pages[ep].length) % 5
              process.stdout.write "."
            else
              process.stdout.write "#{pageAmount[ep] - pages[ep].length}"
          else
            process.stdout.write "\nRemaining (##{ep}): #{pages[ep].join(', ')}" if pages[ep].length

mangaDownload = (vol, ep) ->
  fraction  = if ep.match /\./ then _.last(ep.split('.')) else false # It asks for last part
  ep        = ep.split('.')[0] # It asks for the 1st part.

  # program is the commander lib
  # format is
  # 1 -> url/v01/c001
  # 2 -> url/v1/c1
  # 3 -> url/c1
  # 4 -> url/c001.1.2
  format    = mangaUrls[program.manga].format

  # 'http://mangafox.me/manga/one_piece/v01/c001/' is format 1

  format    = 4 if format is 2 and not vol
  uri       = switch format
              when 1 then "#{mangaUrls[program.manga].url}/v#{if vol is 'TBD' then 'TBD' else padding(vol, 2)}/c#{padding(ep, 3)}/"
              when 2 then "#{mangaUrls[program.manga].url}/v#{vol}/c#{ep}/"
              when 3 then "#{mangaUrls[program.manga].url}/v#{padding(vol, 2)}/c#{padding(ep, 3)}#{if fraction then '.' + fraction else ''}/"
              when 4 then "#{mangaUrls[program.manga].url}/c#{ep}/"
              else        "#{mangaUrls[program.manga].url}/c#{padding(ep, 3)}#{if fraction then '.' + fraction else ''}/"
  uri      += "e#{program.ver}/" if program.ver
  paddedVol = padding(vol, 3)
  paddedEp  = padding(ep, 3)
  paddedEp += ".#{fraction}" if fraction
  host      = mangaUrls[program.manga].url.match(/http:\/\/[.\w\d]+\//) || []
  host      = host[0]

  # mangapark is diff
  if host is 'http://mangapark.com/'
    if program.pages
      uri += "10-#{program.pages}"
    else
      uri += 'all'

  console.log uri

  # code
  # return request({
  #      uri: uri
  #   }, function(err, res, body) {
  #   .....
  # });
  # so uri: uri, it is a json input, (err, res, body) is the callback 
  request uri: uri, (err, res, body) ->

    if err or res.statusCode isnt 200
      console.log clc.red "Oops, something went wrong #{'(Error: ' + res.statusCode + ')'if res}"
      return false

    $ = cheerio.load(body)

    # Tap-in for mangapark.com
    if host.match(/mangapark/)
      imgs           = $('img.img')
      pages[ep]      = imgs.map (i) -> i
      pageAmount[ep] = pages[ep].length
      imgs.each (i) -> imageDownload @attr('src'), i, paddedVol, paddedEp, ep

    # Other sites
    else
      # host === http://mangafox.me/
      # uri === 'http://mangafox.me/manga/one_piece/v01/c001/'
      pageAmount[ep] = switch host
                   when 'http://mangafox.me/' then $('form#top_bar select.m option').length # 56 pages
                   else                            $('section.readpage_top select.wid60 option').length
      pages[ep] = program.pages || [0..pageAmount[ep]] # so it becomes [1, 2, 3, ... 56]
      # uri = uri.slice(0, -1) if uri.match /\/$/  # Remove trailing `/`

      console.log clc.green "Downloading up to #{pages[ep].length} page(s)"
      for i in _.clone pages[ep]
      
        do (i) ->
          request uri: "#{uri}#{ if i > 0 then i + '.html' else ''  }", followRedirect: false, (err, res, body) ->
            $$ = cheerio.load(body)

            if err or res.statusCode isnt 200 
              pages[ep].splice(pages[ep].indexOf(i), 1)
            else
              img = $$('img#image')

              unless img.length
                my_tmp_1 = pages[ep]; #[1, 2, .... 56]
                my_tmp_2 = pages[ep].indexOf(i) # 7
                my_tmp_3 = pages[ep].splice(pages[ep].indexOf(i), 1) # [7]

                pages[ep].splice(pages[ep].indexOf(i), 1)
              else
                
                # test
                debugger


                # imgUri === 'http://c.mfcdn.net/store/manga/106/01-001.0/compressed/f002.jpg', from img src
                imgUri = switch host
                         when 'http://mangafox.me/' then img.attr('onerror').match(/http.+jpg/)[0]  # New manga seems to fallback to another CDN
                         else                            img.attr('src')

                # Rerender mode for mangahere
                imgUri = switch program.rerender
                         when '0' then imgUri.replace(/.\.m.cdn\.net/, 'm.mhcdn.net')
                         when '1' then imgUri.replace(/.\.m.cdn\.net/, 's.mangahere.com')
                         when '2' then imgUri.replace(/.\.m.cdn\.net/, 'z.mfcdn.net')
                         else          imgUri

                console.log imgUri if program.pages
                imageDownload imgUri, i, paddedVol, paddedEp, ep

mangaList = ->
  for name, url of mangaUrls
    do (name, url) ->
      _host = mangaUrls[name].url.match(/http:\/\/[.\w\d]+\//) || []
      _host = _host[0]

      request uri: "#{mangaUrls[name].url}/", followRedirect: true, (err, res, body) ->
        $          = cheerio.load(body)
        label      = switch _host
                     when 'http://mangafox.me/'   then $('a.tips').first().text().trim()
                     when 'http://mangapark.me/' then $('.stream:last-child ul.chapter li span a').first().text().trim().replace(/\n/, '').replace(/(\s+|\t)/, ' ')
                     else                              $('div.detail_list span.left a.color_0077').first().text().trim()
        labelNum   = _.last(label.split(' '))
        labelNum   = ~~(_.last(labelNum.split('.')))
        folderPath = "./manga/#{name}"

        if fs.existsSync(folderPath)
          fs.readdir folderPath, (e, folders) ->
            _.remove(folders, (x) -> x is '.DS_Store')
            latestFolder = ~~(_.last(_.last(folders).split('-'))) if folders.length
            color = if latestFolder is labelNum then clc.green else clc.red

            console.log "[#{clc.yellow name}] #{label} (local: #{color(if latestFolder? then latestFolder else '-')}/#{labelNum})"

episodeList = ->
  unless program.manga
    console.log 'Error: please specify manga'
    return

  request uri: "#{mangaUrls[program.manga].url}/", followRedirect: false, (err, res, body) ->
    $ = cheerio.load(body)
    $('.stream').each ->
      console.log @.find('h3').text()
      @.find('ul.chapter span a').each ->
        console.log @.text().trim()
      console.log()

##############################################################################
# App Kickoff!
##############################################################################

if program.list then mangaList()
else if program.eplist then episodeList()
else if program.manga and program.episode
  episodes =  [program.episode[0]..(program.episode[1] || program.episode[0])]
  for ep in episodes
    mangaDownload(program.volume || 0, ep.toString())
else
  console.log 'Error: please specify manga, volume and episode'
