require 'colors'
path       = require 'path'
fs         = require 'fs'
libxml     = require 'libxmljs'
spawn      = require('child_process').spawn


class $

  @onTaskNamespace: (taskName, scope) ->
    names = taskName.split(':')
    taskName = names.pop()
    rec = ->
      if names.length == 0
        scope taskName
      else
        namespace names.shift(), rec
    rec()

  @mem: (fn) -> (args ...)->
    (arguments.callee['memo'] ||= {})[[].concat args] ||= fn.apply this, args

  @pathSearch: (bin, dirs = process.env.PATH.split(':')) ->
    return path.join(d, bin) for d in dirs when fs.existsSync path.join(d, bin)

  @_: (args ...) -> path.join.apply(path, [process.cwd()].concat(args))

  @E: (args ...) -> path.join.apply(path, [__dirname, '../etc'].concat(args))

  @pkg: JSON.parse fs.readFileSync path.join(__dirname, '../package.json'), 'utf-8'

  @main: -> require('./tintan/main') Tintan

  @tasks: (tintan)-> require('./tintan/tasks') tintan

  @home: @mem ->
    dirs = [process.env.TI_HOME
            '/Library/Application Support/Titanium'
            path.join(process.env.HOME, 'Library/Application Support/Titanium')
            path.join(process.env.HOME, '.titanium')
    ]
    return d for d in dirs when fs.existsSync d

  @os: {
    'linux':  'linux'
    'darwin': 'osx'
    'win32':  'win'
  }[require('os').platform()]

  @ios_version: @mem ->
    iphone_dir = path.join(process.env.HOME, 'Library', 'Application Support', 'iPhone Simulator')
    if fs.existsSync iphone_dir
      return process.env.IOS_VERSION if process.env.IOS_VERSION &&
        fs.existsSync(path.join(iphone_dir, process.env.IOS_VERSION))
      fs.readdirSync(iphone_dir).sort()[-1..][0]

  @android_version: @mem ->
    android_dir = path.join(@android_home(), 'platforms')
    if fs.existsSync android_dir
      return process.env.ANDROID_VERSION if process.env.ANDROID_VERSION &&
        fs.existsSync(path.join(android_dir, 'android-' + (process.env.ANDROID_VERSION - 1)))
      (d.split('-')[1] for d in fs.readdirSync(android_dir)).sort((a,b)-> a - b)[-1..][0]

  @android_home: @mem ->
    brew_location = '/usr/local/Cellar/android-sdk'
    if process.env.ANDROID_SDK && fs.existsSync process.env.ANDROID_SDK
      process.env.ANDROID_SDK
    else if fs.existsSync brew_location
      path.join brew_location, fs.readdirSync(brew_location).sort()[-1..][0]

  @platform: process.env.TI_PLATFORM || {osx: 'iphone'}[@os] || 'android'

  @sdk: @mem ->
    if fs.existsSync process.env.TI_SDK
      process.env.TI_SDK
    else
      fs.readdirSync(path.join(@home(), 'mobilesdk', @os)).sort()[-1..][0]

  @py: @mem ->
    return py for py in [process.env.PYTHON, process.env.TI_PYTHON,
                         process.env.PYTHON_EXECUTABLE] when fs.existsSync py
    @pathSearch 'python'

  @titan: (args ...)->
    @tipy.apply(this, [['titanium.py'], args])

  @fastdev: (args ...)=> @titan.apply this, ['fastdev'].concat(args || [])

  @tipy: (ary, args ..., cb)->
    unless cb instanceof Function
      if args?.length then args.push cb else args = cb
      cb = ->
    tool = path.join.apply(path, [@home(), 'mobilesdk', @os, @sdk()].concat(ary))
    p = spawn @py(), [tool].concat(args)
    p.stdout.on 'data', (data)-> process.stdout.write data
    p.stderr.on 'data', (data)-> process.stderr.write data
    p.on 'exit', cb

class Config

  DEFAULT_OPTIONS =
    verbose: true
    debug: false
    debug_address: '127.0.0.1'
    debug_port: '5858'
    iced: false
    android_device: ''
    android_devices: []

  file: -> $.E('tintan.config')

  load: ->
    @options = {}
    if !fs.existsSync(@file())
      @options[k] = v for k,v of DEFAULT_OPTIONS when !@options.hasOwnProperty(k)
      @save()
    else
      @options = JSON.parse(fs.readFileSync(@file(), 'utf-8'))

  save: ->
    if @options
      fs.writeFileSync(@file(), JSON.stringify(@options, undefined, 2), 'utf-8')
    else
      console.log('Nothing to save.')

  init: ->
    @load()
    @options[k] = v for k,v of DEFAULT_OPTIONS when !@options.hasOwnProperty(k)
    @save()

  display: ->
    @load()
    console.log(k + ': ' + v) for k, v of @options when @options.hasOwnProperty(k)

  set: (opts = {}) ->
    @load()
    for k, v of opts
      if @options.hasOwnProperty(k)
        @options[k] = v
        console.log('' + k + ' set to ' + v)
        @save()
      else
        console.log('Unknown option: ' + k)

  get: (option) ->
    @load()
    result = null
    if @options.hasOwnProperty(option)
      if @options[option] is 'true'
        result = true
      else if @options[option] is 'false'
        result = false
      else
        result = @options[option]
    return result

  promptForNext: (i) =>
    if i < 0
      return
    key = @config_opts[i]['k']
    value = @config_opts[i]['v']
    process.stdout.write(key + ':' + value + ', new value: ')
    process.stdin.resume()
    process.stdin.on('data', (text) =>
      process.stdin.removeAllListeners('data')
      text = text.replace(/(\r\n|\n|\r)/gm,"")
      ans = text
      if typeof(@options[key]) is 'boolean'
        lowerText = '' + text.toLowerCase()

        switch lowerText
          when 't', 'true', 'tru', 'tr'
            ans = true
            break
          when 'f', 'false', 'fal', 'fa', 'fals'
            ans = false
            break

      process.stdin.pause()
      if ans is ''
        @promptForNext(--i)
      else
        @options[key] = ans
        @save()
        @promptForNext(--i)
    )
    @

  promptForAll: =>
    @load()
    @config_opts = []
    process.stdin.setEncoding('utf8')
    i = 0
    for k, v of @options when @options.hasOwnProperty(k)
      @config_opts.push({k, v})
      i++

    @promptForNext(i-1)

class AppXML

  file: -> $._('tiapp.xml')
  
  exist: -> fs.existsSync @file()

  constructor: ->
    throw "Missing Titanium file #{@file()}".red unless @exist()
    @doc = libxml.parseXmlString fs.readFileSync @file(), 'utf-8'

  plugin: -> @doc.get "./plugins/plugin[contains(text(),'tintan')]"

  id: -> @doc.get('./id').text()

  guid: -> @doc.get('./guid').text()

  name: -> @doc.get('./name').text()

  version: ->
    v = @doc.get('./version').text().split '.'
    if v.length < 3
      v = v.concat('0' for i in [0 .. (2 - v.length)])
    v.join '.'

  targets: (devices ...)->
    if devices.length > 0
      enabled = (device for device in devices when !!@doc.
        get('./deployment-targets/target[@device="' + device +
            '" and contains(text(), "true")]'))
      enabled.length == devices.length
    else
      @doc.find('./deployment-targets/target[contains(text(), "true")]/@device')
          .map (i)-> i.text()


class Tintan

  @$ = $
  @version: $.pkg.version
  @appXML: $.mem -> new AppXML
  @config = -> new Config


module.exports = Tintan
