#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#include <X11/Xatom.h>
#include <X11/Xlib.h>
#endif

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

static void first_frame_cb(MyApplication* self, FlView* view) {
  // Show the top-level only when first Flutter frame arrives
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

#ifdef GDK_WINDOWING_X11
static void apply_x11_desktop_hints(GtkWindow* window) {
  GdkWindow* gdk_window = gtk_widget_get_window(GTK_WIDGET(window));
  if (!GDK_IS_X11_WINDOW(gdk_window))
    return;

  Display* display = GDK_DISPLAY_XDISPLAY(gdk_window_get_display(gdk_window));
  Window x11_window = GDK_WINDOW_XID(gdk_window);

  Atom net_wm_window_type = XInternAtom(display, "_NET_WM_WINDOW_TYPE", False);
  Atom net_wm_window_type_desktop = XInternAtom(display, "_NET_WM_WINDOW_TYPE_DESKTOP", False);
  XChangeProperty(display, x11_window, net_wm_window_type, XA_ATOM, 32,
                  PropModeReplace, (unsigned char*)&net_wm_window_type_desktop, 1);

  Atom net_wm_state = XInternAtom(display, "_NET_WM_STATE", False);
  Atom below = XInternAtom(display, "_NET_WM_STATE_BELOW", False);
  Atom sticky = XInternAtom(display, "_NET_WM_STATE_STICKY", False);
  Atom skip_taskbar = XInternAtom(display, "_NET_WM_STATE_SKIP_TASKBAR", False);
  Atom skip_pager = XInternAtom(display, "_NET_WM_STATE_SKIP_PAGER", False);

  Atom states[] = { below, sticky, skip_taskbar, skip_pager };
  XChangeProperty(display, x11_window, net_wm_state, XA_ATOM, 32,
                  PropModeReplace, (unsigned char*)states, G_N_ELEMENTS(states));

  // Make sure changes are sent
  XFlush(display);
}
#endif

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window = GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // Make window properties for desktop
  gtk_window_set_decorated(window, FALSE);
  gtk_window_set_skip_taskbar_hint(window, TRUE);
  gtk_window_set_skip_pager_hint(window, TRUE);
  gtk_window_set_keep_below(window, TRUE);
  gtk_window_set_accept_focus(window, FALSE);

  // Make window app-paintable and request RGBA visual if available
  gtk_widget_set_app_paintable(GTK_WIDGET(window), TRUE);
  GdkScreen* screen = gtk_widget_get_screen(GTK_WIDGET(window));
  if (GDK_IS_SCREEN(screen)) {
    GdkVisual* rgba_visual = gdk_screen_get_rgba_visual(screen);
    if (rgba_visual) {
      // Use the RGBA visual to get alpha channel
      gtk_widget_set_visual(GTK_WIDGET(window), rgba_visual);
    }
  }

  // Resize/move to cover primary monitor
  GdkRectangle monitor_geometry;
  GdkDisplay* display = gdk_display_get_default();
  if (display) {
    GdkMonitor* mon = gdk_display_get_primary_monitor(display);
    if (!mon) mon = gdk_display_get_monitor(display, 0);
    if (mon) {
      gdk_monitor_get_geometry(mon, &monitor_geometry);
      gtk_window_move(window, monitor_geometry.x, monitor_geometry.y);
      gtk_window_set_default_size(window, monitor_geometry.width, monitor_geometry.height);
    } else {
      // fallback: fullscreen
      gtk_window_fullscreen(window);
    }
  } else {
    gtk_window_fullscreen(window);
  }

  // Realize early so we can set X11 properties and background RGBA
  gtk_widget_realize(GTK_WIDGET(window));

#ifdef GDK_WINDOWING_X11
  apply_x11_desktop_hints(window);

  // Set the X11 window background to transparent (if supported)
  GdkWindow* gdk_window = gtk_widget_get_window(GTK_WIDGET(window));
  if (GDK_IS_X11_WINDOW(gdk_window)) {
    Display* dpy = GDK_DISPLAY_XDISPLAY(gdk_window_get_display(gdk_window));
    Window xid = GDK_WINDOW_XID(gdk_window);
    // Setting background pixmap to None and using composite should allow alpha
    XSetWindowBackgroundPixmap(dpy, xid, None);
    XClearWindow(dpy, xid);
    XFlush(dpy);
  }
#endif

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);

  // Important: set FlView background transparent before adding to container
  GdkRGBA transparent;
  gdk_rgba_parse(&transparent, "rgba(0,0,0,0)");
  fl_view_set_background_color(view, &transparent);

  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));
  gtk_widget_show(GTK_WIDGET(view));

  // show the window (the first-frame callback will show top-level)
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb), self);

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));
  gtk_widget_show(GTK_WIDGET(window));
}

static gboolean my_application_local_command_line(GApplication* application, gchar*** arguments, int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
     g_warning("Failed to register: %s", error->message);
     *exit_status = 1;
     return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;
  return TRUE;
}

static void my_application_startup(GApplication* application) {
  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

static void my_application_shutdown(GApplication* application) {
  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line = my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  g_set_prgname(APPLICATION_ID);
  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID,
                                     "flags", G_APPLICATION_NON_UNIQUE,
                                     nullptr));
}
