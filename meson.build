project('singularity-podcasts', ['vala', 'c'],
  version: '0.1.0',
  meson_version: '>= 0.59.0'
)

i18n = import('i18n')
add_project_arguments('-DGETTEXT_PACKAGE="singularity-podcasts"', language: 'c')
subdir('po')

gtk_dep   = dependency('gtk4')
gee_dep   = dependency('gee-0.8')
soup_dep  = dependency('libsoup-3.0')
json_dep  = dependency('json-glib-1.0')
xml_dep   = dependency('libxml-2.0')
gst_dep   = dependency('gstreamer-1.0')
gio_dep   = dependency('gio-2.0')
pixbuf_dep = dependency('gdk-pixbuf-2.0')

libsingularity_dep = dependency('singularity-1.0',
  fallback: ['libsingularity', 'libsingularity_dep']
)

if not meson.is_subproject() and libsingularity_dep.type_name() == 'internal'
  libsingularity_vapi_dir = join_paths(meson.project_build_root(), 'subprojects', 'libsingularity')
  add_project_arguments(['--vapidir=' + libsingularity_vapi_dir], language: 'vala')
endif

core_sources = files('src/chapters.vala', 'src/feed.vala', 'src/opml.vala', 'src/itunes.vala', 'src/format.vala', 'src/library.vala', 'src/net.vala', 'src/queue.vala', 'src/sleep_timer.vala')
math_dep = meson.get_compiler('c').find_library('m')

executable('singularity-podcasts',
  core_sources + files('src/effects.vala', 'src/artwork.vala', 'src/player.vala', 'src/mpris.vala', 'src/downloads.vala', 'src/window.vala', 'src/app.vala'),
  dependencies: [gtk_dep, gee_dep, soup_dep, json_dep, xml_dep, gst_dep, pixbuf_dep, math_dep, libsingularity_dep],
  install: true
)

shared_module('singularity-podcasts-widget',
  files('widget/new_episodes_widget.vala'),
  dependencies: [gtk_dep, gee_dep, json_dep, libsingularity_dep],
  install: true,
  install_dir: get_option('libdir') / 'singularity' / 'widgets'
)
install_data('widget/dev.sinty.podcasts.new-episodes.widget',
  install_dir: get_option('datadir') / 'singularity' / 'widgets'
)

podcasts_test = executable('podcasts-test',
  core_sources + files('src/effects.vala', 'tests/podcasts_test.vala'),
  dependencies: [gee_dep, soup_dep, json_dep, xml_dep, gio_dep, gst_dep, math_dep],
)
test('podcasts', podcasts_test, env: [
  'PODCASTS_FIXTURES=' + meson.current_source_dir() / 'tests' / 'fixtures',
  'TMPDIR=' + meson.current_build_dir(),
])

install_data('data/dev.sinty.podcasts.desktop',
  install_dir: get_option('datadir') / 'applications'
)

install_data('data/dev.sinty.podcasts.gschema.xml',
  install_dir: get_option('datadir') / 'glib-2.0' / 'schemas'
)

install_data('data/dev.sinty.podcasts.json',
  install_dir: get_option('datadir') / 'singularity' / 'app-settings'
)

install_data('data/icons/dev.sinty.podcasts.svg',
  install_dir: get_option('datadir') / 'icons' / 'hicolor' / 'scalable' / 'apps'
)

service_conf = configuration_data()
service_conf.set('bindir', get_option('prefix') / get_option('bindir'))
configure_file(
  input: 'data/dev.sinty.podcasts.service.in',
  output: 'dev.sinty.podcasts.service',
  configuration: service_conf,
  install: true,
  install_dir: get_option('datadir') / 'dbus-1' / 'services'
)
