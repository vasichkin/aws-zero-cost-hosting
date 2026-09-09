function handler(event) {
  var request = event.request;
  var uri = request.uri;

  if (uri.endsWith("/")) {
    request.uri = uri + "index.html";
    return request;
  }

  var lastSegment = uri.substring(uri.lastIndexOf("/") + 1);
  if (lastSegment && !lastSegment.includes(".")) {
    request.uri = uri + "/index.html";
  }

  return request;
}
