# xstartup

This is a simple program launcher meant to be used during session startup. Each application has an independent countdown and can be cancelled or run immediately. It's written with Ruby-GTK2 and should run everywhere where it's available, though it's only tested on Linux.

## Screenshots

[![Settings Window](http://i.imgur.com/FNo4Is.jpg)](http://imgur.com/a/aqLqa#FNo4I)
[![Countdown Window](http://i.imgur.com/HJYGJs.jpg)](http://imgur.com/a/aqLqa#HJYGJ)

## Usage

* `xstartup` - show the settings window
* `xstartup -run` - show the countdown window and run the configured applications

### Settings Window

* Uncheck an application to hide it
* Enter the number of seconds for the application's countdown in the **Timeout** field, or enter **0** to disable the countdown but still show the application
* Enter a Ruby expression in the **Condition** field to dynamically enable the application if the expression is true
* The configuration is stored in `~/.xstartup` in YAML format

### Countdown Window

* Click on an application's icon to start it immediately
* Click on an application's cancel button to skip it
* If no countdowns are left the window will automatically close

