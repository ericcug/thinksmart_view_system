// set the DPMS property of the first connected connector
//   dpms off | on | doze | suspend
#include <stdio.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <xf86drm.h>
#include <xf86drmMode.h>

int main(int argc, char **argv)
{
	int fd = open("/dev/dri/card0", O_RDWR);
	if (fd < 0) { perror("open"); return 1; }
	if (argc < 2) { fprintf(stderr, "usage: dpms on|off|doze|suspend\n"); return 2; }
	uint64_t val = strcmp(argv[1], "on") == 0 ? 0 :
		       strcmp(argv[1], "suspend") == 0 ? 1 :
		       strcmp(argv[1], "off") == 0 ? 3 : 2;
	drmModeRes *res = drmModeGetResources(fd);
	if (!res) { fprintf(stderr, "no resources\n"); return 1; }
	for (int i = 0; i < res->count_connectors; i++) {
		drmModeConnector *c = drmModeGetConnector(fd, res->connectors[i]);
		if (!c) continue;
		if (c->connection != DRM_MODE_CONNECTED) { drmModeFreeConnector(c); continue; }
		drmModeObjectProperties *props =
			drmModeObjectGetProperties(fd, c->connector_id, DRM_MODE_OBJECT_CONNECTOR);
		for (unsigned p = 0; props && p < props->count_props; p++) {
			drmModePropertyRes *pr = drmModeGetProperty(fd, props->props[p]);
			if (pr && strcmp(pr->name, "DPMS") == 0) {
				int ret = drmModeConnectorSetProperty(fd, c->connector_id,
						pr->prop_id, val);
				printf("connector %u DPMS=%llu ret=%d\n",
				       c->connector_id, (unsigned long long)val, ret);
			}
			if (pr) drmModeFreeProperty(pr);
		}
		if (props) drmModeFreeObjectProperties(props);
		drmModeFreeConnector(c);
	}
	drmModeFreeResources(res);
	close(fd);
	return 0;
}