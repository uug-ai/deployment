const expected = {
  _id: "loadtest-rs",
  members: [{ _id: 0, host: "mongo:27017" }],
};

let config;
try {
  config = rs.conf();
} catch (error) {
  if (error.code !== 94) {
    throw error;
  }
}

if (config) {
  if (
    config._id !== expected._id ||
    config.members.length !== 1 ||
    config.members[0].host !== expected.members[0].host
  ) {
    throw new Error("Refusing to reconfigure an unexpected replica set");
  }
} else {
  const result = rs.initiate(expected);
  if (!result.ok) {
    throw new Error(`Replica set initialization failed: ${JSON.stringify(result)}`);
  }
}

for (let attempt = 0; attempt < 60; attempt++) {
  if (db.adminCommand({ hello: 1 }).isWritablePrimary) {
    print("Dedicated load-test replica set is writable");
    quit(0);
  }
  sleep(1000);
}

throw new Error("Timed out waiting for the load-test primary");
