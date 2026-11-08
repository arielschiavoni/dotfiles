rex.host({
  label = "devbox",
  endpoint = os.getenv("HOME") .. "/.ssh/rex-devbox.sock",
})
