#!/usr/bin/env ruby
=begin

  xstartup 0.1 - Copyright 2006 Markus Koller

  This program is free software; you can redistribute it and/or modify
  it under the terms of the GNU General Public License version 2 as
  published by the Free Software Foundation

  $Id: xstartup.rb 17 2011-04-11 19:48:05Z toupeira $

=end

require 'gtk2/base'
require 'yaml'

CONFIG = File.join ENV['HOME'] || ENV['USERPROFILE'] || '', '.xstartup'

def main
  Gtk.init([])
  if ARGV.first == '-run'
    Popup.new
  elsif ARGV.first
    name = File.basename($0)
    puts
    puts "  Usage: #{name}       Show settings"
    puts "         #{name} -run  Run configured applications"
    puts
    exit
  else
    Settings.new
  end
  Gtk.main
end

class Popup < Gtk::Window
  attr_reader :tips

  def initialize
    super
    set_title('Startup')
    set_type_hint(Gdk::Window::TYPE_HINT_SPLASHSCREEN)
    set_icon(render_icon(Gtk::Stock::EXECUTE, Gtk::IconSize::MENU))
    set_window_position(Gtk::Window::POS_CENTER)
    set_decorated(false)
    set_border_width(15)
    stick
    signal_connect('destroy') { Gtk.main_quit }

    @tips = Gtk::Tooltips.new

    vbox = Gtk::VBox.new
    vbox.spacing = 20
    self << vbox

    # Items
    @itembox = Gtk::VBox.new
    @itembox.spacing = 10
    vbox << @itembox

    buttons = Gtk::HBox.new
    buttons.spacing = 5
    vbox << (Gtk::Alignment.new(0.5, 0.5, 0, 0) << buttons)

    # 'Run all' button
    button = Gtk::Button.new
    button.relief = Gtk::RELIEF_NONE
    button.signal_connect('clicked') do
      Item.items.each do |i|
        i.run if i.table.sensitive?
      end
    end
    buttons << button

    hbox = Gtk::HBox.new
    hbox.spacing = 5
    button << hbox

    hbox << Gtk::Image.new(Gtk::Stock::EXECUTE, Gtk::IconSize::MENU)

    label = Gtk::Label.new('<b>_Run all</b>')
    label.use_markup = true
    label.use_underline = true
    hbox << label

    # 'Cancel all' button
    button = Gtk::Button.new
    button.relief = Gtk::RELIEF_NONE
    button.signal_connect('clicked') { Gtk.main_quit }
    buttons << button

    hbox = Gtk::HBox.new
    hbox.spacing = 5
    button << hbox

    hbox << Gtk::Image.new(Gtk::Stock::STOP, Gtk::IconSize::MENU)

    label = Gtk::Label.new('<b>_Cancel all</b>')
    label.use_markup = true
    label.use_underline = true
    hbox << label

    load
    show_all
  end

  def load
    return unless File.readable? CONFIG
    YAML.load_file(CONFIG).each do |item|
      next unless item[:enabled]
      if item[:condition] and !item[:condition].empty?
        next unless eval(item[:condition]) rescue next
      end
      @itembox << Item.new(self, item).table
    end
    exit if Item.items.empty?
  end

  class Item
    attr_reader :table

    @@items = []
    @@pending = 0

    def self.items; @@items end

    def initialize(window, item)
      item.each do |key,value|
        instance_variable_set('@'+key.to_s, value)
      end

      @table = Gtk::Table.new(2, 3)

      # Run button
      @button = Gtk::Button.new
      @button.relief = Gtk::RELIEF_NONE
      @button.signal_connect('clicked') { run }
      window.tips.set_tip(@button, 'Run', nil)
      @table.attach(@button, 0, 1, 0, 2)

      icon = Gtk::Image.new
      icon.set_size_request(32, 32)
      begin
        icon.pixbuf = Gdk::Pixbuf.new(@icon).scale(32, 32)
      rescue
        icon.pixbuf = window.render_icon(Gtk::Stock::EXECUTE, Gtk::IconSize::DND, '')
      end
      @button << icon

      # Name label
      label = Gtk::Label.new("<span size='large'><b>#@name</b></span>")
      label.use_markup = true
      label.set_alignment(0, 0.5)
      label.set_padding(5, 0)
      @table.attach(label, 1, 2, 0, 1)

      # Progressbar
      @progress = Gtk::ProgressBar.new
      if RUBY_PLATFORM =~ /mswin32/
        @progress.set_size_request(-1, 20)
      else
        @progress.set_size_request(-1, 16)
      end
      @table.attach(@progress, 1, 2, 1, 2, 0, 0, 0)

      # Cancel button
      button = Gtk::Button.new
      button.relief = Gtk::RELIEF_NONE
      button.signal_connect('clicked') { cancel }
      button << Gtk::Image.new(Gtk::Stock::STOP, Gtk::IconSize::MENU)
      window.tips.set_tip(button, 'Cancel', nil)
      @table.attach(button, 2, 3, 0, 2)

      if @timeout.zero?
        button.sensitive = false
        @progress.text = 'Click to run'
      else
        @progress.fraction = 1
        @id = Gtk.timeout_add(50) { update }
        @@pending += 1
      end

      @@items << self
      @table.show_all
    end

    def run
      if RUBY_PLATFORM =~ /mswin32/
        system("start /b #@command")
      else
        system("(#@command) &>/dev/null &")
      end

      Gtk.timeout_remove(@id) if @id

      @progress.text = 'Running'
      @table.sensitive = false
      done unless @timeout.zero?
    end

    def update
      pos = @progress.fraction - (0.05 / @timeout)
      if pos > 0
        @progress.fraction = pos
        @progress.text = "Running in #{(pos * @timeout).ceil}s"
        true
      else
        run
        false
      end
    end

    def done
      @progress.fraction = 0
      @table.sensitive = false
      @@pending -= 1
      Gtk.main_quit if @@pending.zero?
    end

    def cancel
      Gtk.timeout_remove(@id) if @id
      @progress.text = 'Cancelled'
      done
    end
  end
end

class Settings < Gtk::Window
  NAME, COMMAND, ICON, TIMEOUT, CONDITION, ENABLED = *(0..5)

  def initialize
    super
    set_title('Startup Programs')
    set_icon(render_icon(Gtk::Stock::EDIT, Gtk::IconSize::MENU))
    set_border_width(5)
    set_default_size(500, 400)
    signal_connect('destroy') { Gtk.main_quit }

    vbox = Gtk::VBox.new
    vbox.spacing = 5
    self << vbox

    @list = Gtk::ListStore.new(
      String,     # NAME
      String,     # COMMAND
      String,     # ICON
      Integer,    # TIMEOUT
      String,     # CONDITION
      TrueClass   # ENABLED
    )

    sw = Gtk::ScrolledWindow.new
    sw.set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
    vbox << sw

    view =  Gtk::TreeView.new(@list)
    view.reorderable = true
    view.rules_hint = true
    view.signal_connect('row-activated') { |v,path,c| edit(path) }
    sw << view

    # Enabled column
    render = Gtk::CellRendererToggle.new
    render.signal_connect('toggled') do |cell, path|
      row = @list.get_iter(path)
      row[ENABLED] ^= 1
    end
    column = Gtk::TreeViewColumn.new('', render, :active => ENABLED)
    column.sort_column_id = ENABLED
    view.append_column(column)

    # Icon column
    render = Gtk::CellRendererPixbuf.new
    column = Gtk::TreeViewColumn.new('Icon', render)
    column.set_cell_data_func(render) do |column, cell, model, row|
      begin
        cell.pixbuf = Gdk::Pixbuf.new(row[ICON]).scale(20, 20)
      rescue
        cell.pixbuf = render_icon(Gtk::Stock::EXECUTE, Gtk::IconSize::BUTTON, '')
      end
    end
    view.append_column(column)

    # Name column
    render = Gtk::CellRendererText.new
    column = Gtk::TreeViewColumn.new('Name', render, :text => NAME)
    column.sort_column_id = NAME
    view.append_column(column)

    # Command column
    render = Gtk::CellRendererText.new
    render.ellipsize = Pango::ELLIPSIZE_END

    column = Gtk::TreeViewColumn.new('Command', render, :text => COMMAND)
    column.sort_column_id = COMMAND
    column.expand = true
    view.append_column(column)

    # Timeout column
    column = Gtk::TreeViewColumn.new('Timeout', render, :text => TIMEOUT)
    column.sort_column_id = TIMEOUT
    view.append_column(column)

    hbox = Gtk::HBox.new
    hbox.spacing = 4
    vbox.pack_end(hbox, false)

    # 'Add' button
    button = Gtk::Button.new(Gtk::Stock::ADD)
    hbox << button
    button.signal_connect('clicked') do
      row = @list.append
      row[ENABLED] = true
      view.set_cursor(row.path, nil, false)
      view.row_activated(row.path, view.get_column(NAME))
    end

    # 'Remove' button
    button = Gtk::Button.new(Gtk::Stock::REMOVE)
    hbox << button
    button.signal_connect('clicked') do
      if row = view.selection.selected
        path = row.path
        @list.remove(row)
        view.set_cursor(path, nil, false)
      end
    end

    # 'Save' button
    button = Gtk::Button.new(Gtk::Stock::SAVE)
    hbox << button
    button.signal_connect('clicked') { save }

    load
    show_all
  end

  def load
    return unless File.readable? CONFIG
    YAML.load_file(CONFIG).each do |item|
      row = @list.append
      row[NAME] = item[:name]
      row[COMMAND] = item[:command]
      row[ICON] = item[:icon]
      row[TIMEOUT] = item[:timeout]
      row[CONDITION] = item[:condition]
      row[ENABLED] = item[:enabled]
    end
  end

  def save
    items = []
    @list.each do |model, path, row|
      items << {
        :command   => row[COMMAND],
        :name      => row[NAME],
        :icon      => row[ICON],
        :enabled   => row[ENABLED],
        :condition => row[CONDITION],
        :timeout   => row[TIMEOUT]
      }
    end
    open(CONFIG, 'w') { |file| YAML.dump(items, file) }
    Gtk.main_quit
  end

  def edit(path)
    row = @list.get_iter(path)
    dialog = ItemProperties.new(self)
    dialog.load(
      row[NAME],
      row[COMMAND],
      row[ICON],
      row[TIMEOUT],
      row[CONDITION]
    )
    if values = dialog.run
      values.each_with_index { |v,i| row[i] = v }
    end
    dialog.destroy
  end

  class ItemProperties < Gtk::Dialog
    class Label < Gtk::Label
      def initialize(text, widget)
        super
        set_alignment(0.0, 0.5)
        set_use_underline(true)
        set_mnemonic_widget(widget)
      end
    end

    def run
      if super == Gtk::Dialog::RESPONSE_OK
        [
          @name.text,
          @command.text,
          @icon.filename,
          @timeout.value,
          @condition.text
        ]
      end
    end

    def initialize(parent)
      super('Properties', parent, MODAL,
        [Gtk::Stock::CANCEL, RESPONSE_CANCEL],
        [Gtk::Stock::OK, RESPONSE_OK]
      )
      set_default_response(RESPONSE_OK)
      set_default_width(300)

      table = Gtk::Table.new(5, 2)
      table.border_width = 5
      table.row_spacings = 5
      table.column_spacings = 5
      vbox.pack_start(table, false)

      @name = Gtk::Entry.new
      table.attach(@name, 1, 2, 0, 1)

      label = Label.new('_Name:', @name)
      table.attach(label, 0, 1, 0, 1, Gtk::FILL)

      @command = Gtk::Entry.new
      table.attach(@command, 1, 2, 1, 2)

      label = Label.new('Co_mmand:', @command)
      table.attach(label, 0, 1, 1, 2, Gtk::FILL)

      @icon = Gtk::FileChooserButton.new('Icon', Gtk::FileChooser::ACTION_OPEN)
      table.attach(@icon, 1, 2, 2, 3)

      label = Label.new('_Icon:', @icon)
      table.attach(label, 0, 1, 2, 3, Gtk::FILL)

      filter = Gtk::FileFilter.new
      filter.name = 'Images'
      filter.add_pixbuf_formats
      @icon.add_filter(filter)

      filter = Gtk::FileFilter.new
      filter.name = 'All files'
      filter.add_pattern('*')
      @icon.add_filter(filter)

      @timeout = Gtk::SpinButton.new(0, 600, 1)
      table.attach(@timeout, 1, 2, 3, 4)

      label = Label.new('_Timeout:', @timeout)
      table.attach(label, 0, 1, 3, 4, Gtk::FILL)

      @condition = Gtk::Entry.new
      @condition.signal_connect('changed') do
        begin
          eval(@condition.text)
          color = 'dark green'
        rescue Exception => exc
          puts exc.message
          color = 'red'
        end
        @condition.modify_text(Gtk::STATE_NORMAL, Gdk::Color.parse(color))
      end
      table.attach(@condition, 1, 2, 4, 5)

      label = Label.new('Con_dition:', @condition)
      table.attach(label, 0, 1, 4, 5, Gtk::FILL)

      table.show_all
    end

    def load(name, command, icon, timeout, condition)
      @name.text = name.to_s
      @command.text = command.to_s
      @icon.filename = icon if File.exists? icon.to_s
      @timeout.value = timeout.to_f rescue 0
      @condition.text = condition.to_s
    end
  end
end

main if __FILE__ == $0
