function handler(event) {
  var request = event.request;
  var uri = request.uri;
  if (uri.startsWith("/admin") && !uri.includes(".")) {
    request.uri = "/admin/index.html";
  }
  return request;
}
