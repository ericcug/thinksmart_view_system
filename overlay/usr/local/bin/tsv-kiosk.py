#!/usr/bin/env python3
"""Minimal fullscreen WebKit2GTK kiosk shell for tsv-voice (MOSS 550W).

Loads URL= from /etc/tsv/kiosk.conf (defaults to http://127.0.0.1:8090/).
All Wi-Fi, Bluetooth, Home Assistant, and audio controls live natively inside tsv-voice.
"""
import os
import urllib.error
import urllib.request

import gi

gi.require_version('Gtk', '3.0')
gi.require_version('WebKit2', '4.1')
from gi.repository import GLib, Gtk, WebKit2  # noqa: E402

CONF = '/etc/tsv/kiosk.conf'
BOOT_HTML = """<!doctype html>
<html><head><meta charset="utf-8"><style>
html,body{margin:0;height:100%;background:#050508;color:#e6eef8;font-family:sans-serif;
display:flex;align-items:center;justify-content:center;user-select:none;}
.eye{width:28px;height:28px;border-radius:50%;background:#ff2a2a;box-shadow:0 0 24px #ff2a2a;margin-right:14px;}
</style></head><body><div class="eye"></div><div>MOSS 550W STARTING...</div></body></html>"""


def read_conf():
    conf = {}
    try:
        with open(CONF) as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith('#') or '=' not in line:
                    continue
                k, v = line.split('=', 1)
                conf[k.strip()] = v.strip().strip('"\'')
    except OSError:
        pass
    return conf


def reachable(url):
    try:
        urllib.request.urlopen(url, timeout=1.5).close()
        return True
    except urllib.error.HTTPError:
        return True
    except OSError:
        return False


def main():
    conf = read_conf()
    url = conf.get('URL', 'http://127.0.0.1:8090/')
    for item in conf.get('WEBKIT_ENV', '').split():
        k, _, v = item.partition('=')
        if k:
            os.environ[k] = v

    data_dir = os.path.expanduser('~/.local/share/tsv-kiosk')
    cache_dir = os.path.expanduser('~/.cache/tsv-kiosk')
    manager = WebKit2.WebsiteDataManager(base_data_directory=data_dir, base_cache_directory=cache_dir)
    context = WebKit2.WebContext.new_with_website_data_manager(manager)
    policies = WebKit2.WebsitePolicies(autoplay=WebKit2.AutoplayPolicy.ALLOW)
    view = WebKit2.WebView(web_context=context, website_policies=policies)

    settings = view.get_settings()
    settings.set_enable_smooth_scrolling(True)
    settings.set_media_playback_requires_user_gesture(False)
    policy = {
        'on-demand': WebKit2.HardwareAccelerationPolicy.ON_DEMAND,
        'always': WebKit2.HardwareAccelerationPolicy.ALWAYS,
    }.get(conf.get('GPU', 'on-demand'), WebKit2.HardwareAccelerationPolicy.NEVER)
    settings.set_hardware_acceleration_policy(policy)

    state = {'loaded': False}

    def try_load():
        if state['loaded']:
            return False
        if reachable(url):
            state['loaded'] = True
            view.load_uri(url)
            return False
        return True

    def on_load_failed(_view, _event, _uri, error):
        if error.matches(WebKit2.NetworkError.quark(), WebKit2.NetworkError.CANCELLED):
            return False
        state['loaded'] = False
        view.load_html(BOOT_HTML, 'about:blank')
        GLib.timeout_add_seconds(1, try_load)
        return True

    def on_terminated(*_args):
        state['loaded'] = False
        GLib.timeout_add_seconds(1, try_load)

    view.connect('load-failed', on_load_failed)
    view.connect('web-process-terminated', on_terminated)
    view.connect('context-menu', lambda *_args: True)
    view.connect('touch-event', lambda _view, event: not event.touch.emulating_pointer)

    window = Gtk.Window(title='TSV Kiosk')
    window.add(view)
    window.connect('destroy', Gtk.main_quit)
    window.fullscreen()
    window.show_all()

    if not try_load():
        pass
    else:
        view.load_html(BOOT_HTML, 'about:blank')
        GLib.timeout_add_seconds(1, try_load)

    Gtk.main()


if __name__ == '__main__':
    main()
