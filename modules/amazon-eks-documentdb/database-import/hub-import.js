const database = db.getSiblingDB('Kerberos');
const ownerUsername = 'example-user';
const applicationUsername = 'example-application';
const zeroObjectId = ObjectId('000000000000000000000000');
const ownerCreatedAt = ISODate('2016-09-20T09:27:58.811Z');
const ownerUpdatedAt = ISODate('2020-06-14T05:01:35.000Z');

function upsert(collection, id, values) {
  const objectId = typeof id === 'string' ? ObjectId(id) : id;
  const result = database.getCollection(collection).updateOne(
    { _id: objectId },
    { $set: values },
    { upsert: true },
  );

  if (!result.acknowledged) {
    throw new Error(`Upsert was not acknowledged for ${collection}/${id}`);
  }
}

function resolveUserId(username) {
  const users = database.users.find(
    { username },
    { _id: 1 },
  ).limit(2).toArray();
  if (users.length > 1) {
    throw new Error(`Cannot import duplicate username: ${username}`);
  }
  if (users.length === 1) {
    if (!users[0]._id || typeof users[0]._id.toHexString !== 'function') {
      throw new Error(`Existing user ${username} does not have an ObjectId _id`);
    }
    return users[0]._id;
  }
  return ObjectId();
}

function insertIfMissing(collection, id, values) {
  const result = database.getCollection(collection).updateOne(
    { _id: id },
    { $setOnInsert: values },
    { upsert: true },
  );

  if (!result.acknowledged) {
    throw new Error(`Insert was not acknowledged for ${collection}/${id}`);
  }
}

function setObjectIdIfMissing(collection, id, field, value) {
  const result = database.getCollection(collection).updateOne(
    {
      _id: id,
      $or: [
        { [field]: { $exists: false } },
        { [field]: null },
        { [field]: zeroObjectId },
      ],
    },
    { $set: { [field]: value } },
  );

  if (!result.acknowledged) {
    throw new Error(`Initialisation was not acknowledged for ${collection}.${field}`);
  }
}

const ownerId = resolveUserId(ownerUsername);
const applicationId = resolveUserId(applicationUsername);

// Login: example-user / example-password
upsert('users', ownerId, {
  username: ownerUsername,
  email: 'example-user@email.com',
  password: '$2a$10$jwLcD/.UT/1WLK7ct1XuHewI3GQXwW3zerPhCCs7QDrReEuIHbVYi',
  role: 'owner',
  google2fa_enabled: false,
  timezone: 'Europe/Brussels',
  isActive: NumberLong('1'),
  registerToken: '',
  updated_at: ISODate('2020-06-14T05:01:35.000Z'),
  created_at: ISODate('2016-09-20T09:27:58.811Z'),
  amazon_secret_access_key: 'K6rRLBI1xxxCk3C1H',
  amazon_access_key_id: 'AKIAxxxxxxG5Q',
  card_brand: 'Visa',
  card_last_four: '0000',
  card_status: 'ok',
  card_status_message: null,
});

insertIfMissing('organisation', ownerId, {
  name: ownerUsername,
  ownerId,
  isActive: true,
  settings: {
    timezone: 'Europe/Brussels',
  },
  audit: {
    createdBy: ownerId.toHexString(),
    createdAt: ownerCreatedAt,
    updatedBy: ownerId.toHexString(),
    updatedAt: ownerUpdatedAt,
    lastAction: 'organisation.created',
  },
});

const membershipResult = database.organisation_users.updateOne(
  {
    userId: ownerId,
    organisationId: ownerId,
  },
  {
    $setOnInsert: {
      userId: ownerId,
      organisationId: ownerId,
      status: 'active',
      invitedBy: ownerId,
      joinedAt: ownerCreatedAt,
      audit: {
        createdBy: ownerId.toHexString(),
        createdAt: ownerCreatedAt,
        updatedBy: ownerId.toHexString(),
        updatedAt: ownerUpdatedAt,
        lastAction: 'organisation.membership.created',
      },
    },
  },
  { upsert: true },
);
if (!membershipResult.acknowledged) {
  throw new Error('Owner organisation membership was not acknowledged');
}

insertIfMissing('project', ownerId, {
  organisationId: ownerId,
  name: 'Project 1',
  slug: 'project-1',
  isActive: true,
  audit: {
    createdBy: ownerId.toHexString(),
    createdAt: ownerCreatedAt,
    updatedBy: ownerId.toHexString(),
    updatedAt: ownerUpdatedAt,
    lastAction: 'project.default.created',
  },
});

setObjectIdIfMissing('users', ownerId, 'organisationId', ownerId);
const importedOwner = database.users.findOne(
  { _id: ownerId, organisationId: { $type: 'objectId' } },
  { organisationId: 1 },
);
if (!importedOwner) {
  throw new Error('Imported owner has an invalid organisationId');
}
setObjectIdIfMissing('users', ownerId, 'projectId', importedOwner.organisationId);

// Admin login: example-application / example-password
upsert('users', applicationId, {
  username: applicationUsername,
  email: 'example-application@email.com',
  password: '$2a$10$jwLcD/.UT/1WLK7ct1XuHewI3GQXwW3zerPhCCs7QDrReEuIHbVYi',
  role: 'application',
  google2fa_enabled: false,
  timezone: 'Europe/Brussels',
  isActive: NumberLong('1'),
  registerToken: '',
  updated_at: ISODate('2020-06-14T05:01:35.000Z'),
  created_at: ISODate('2016-09-20T09:27:58.811Z'),
});

upsert('subscriptions', ownerId, {
  name: 'default',
  stripe_id: 'sub_9ECyjjMz3R7etK',
  stripe_plan: 'enterprise',
  quantity: 1,
  trial_ends_at: null,
  ends_at: null,
  user_id: ownerId.toHexString(),
  status: 'active',
  updated_at: ISODate('2021-04-27T09:45:30.169Z'),
  created_at: ISODate('2016-09-20T09:35:03.448Z'),
  stripe_status: 'active',
});
setObjectIdIfMissing('subscriptions', ownerId, 'organisation_id', ownerId);

upsert('settings', '5a72c509e17699d18ada9154', {
  key: 'plan',
  map: {
    basic: {
      level: NumberInt(1),
      uploadLimit: NumberInt(100),
      videoLimit: NumberInt(100),
      usage: NumberInt(500),
      analysisLimit: NumberInt(0),
      dayLimit: NumberInt(3),
    },
    premium: {
      level: NumberInt(2),
      uploadLimit: NumberInt(500),
      videoLimit: NumberInt(500),
      usage: NumberInt(1000),
      analysisLimit: NumberInt(0),
      dayLimit: NumberInt(7),
    },
    gold: {
      level: NumberInt(3),
      uploadLimit: NumberInt(1000),
      videoLimit: NumberInt(1000),
      usage: NumberInt(3000),
      analysisLimit: NumberInt(1000),
      dayLimit: NumberInt(30),
    },
    business: {
      level: NumberInt(4),
      uploadLimit: NumberInt(99999999),
      videoLimit: NumberInt(99999999),
      usage: NumberInt(10000),
      analysisLimit: NumberInt(1000),
      dayLimit: NumberInt(30),
    },
    enterprise: {
      level: NumberInt(5),
      uploadLimit: NumberInt(99999999),
      videoLimit: NumberInt(99999999),
      usage: NumberInt(99999999),
      analysisLimit: NumberInt(5000),
      dayLimit: NumberInt(30),
    },
  },
});

upsert('settings', '63f346ec64011a574161cf99', {
  key: 'classifications',
  map: {
    objects: [
      { text: 'Car', value: 'car', icon: 'car' },
      { text: 'Person', value: 'pedestrian', icon: 'pedestrian' },
    ],
  },
});

upsert('settings', '5a43fa12d885eb7da57046b3', {
  key: 'sequence',
  map: { timeBetween: NumberInt(60) },
});

upsert('settings', '5a4d3a6bd885eb7da5e6b297', {
  key: 'throttler',
  map: { waitingTime: NumberInt(60) },
});

upsert('settings', '5a53d0a0d885eb7da53ed5a6', {
  key: 'analysis',
  map: { waitingTime: NumberInt(15) },
});

const importedUsers = database.users.countDocuments({
  _id: {
    $in: [ownerId, applicationId],
  },
});
const importedOwnerUsernames = database.users.countDocuments({ username: ownerUsername });
const importedApplicationUsernames = database.users.countDocuments({ username: applicationUsername });
const importedOwnerSelection = database.users.findOne(
  {
    _id: ownerId,
    organisationId: { $type: 'objectId' },
    projectId: { $type: 'objectId' },
  },
  { organisationId: 1, projectId: 1 },
);
const importedOrganisations = database.organisation.countDocuments({
  _id: ownerId,
  ownerId,
  isActive: true,
});
const importedMemberships = database.organisation_users.countDocuments({
  userId: ownerId,
  organisationId: ownerId,
  status: 'active',
});
const importedProjects = database.project.countDocuments({
  _id: ownerId,
  organisationId: ownerId,
  slug: 'project-1',
  isActive: true,
});
const importedSubscriptions = database.subscriptions.countDocuments({
  _id: ownerId,
  organisation_id: ownerId,
});
const importedSettings = database.settings.countDocuments({
  _id: {
    $in: [
      ObjectId('5a72c509e17699d18ada9154'),
      ObjectId('63f346ec64011a574161cf99'),
      ObjectId('5a43fa12d885eb7da57046b3'),
      ObjectId('5a4d3a6bd885eb7da5e6b297'),
      ObjectId('5a53d0a0d885eb7da53ed5a6'),
    ],
  },
});

if (!importedOwnerSelection) {
  throw new Error('Imported owner is missing ObjectId organisation/project selections');
}
const selectedOrganisationExists = database.organisation.countDocuments({
  _id: importedOwnerSelection.organisationId,
});
const selectedProjectExists = database.project.countDocuments({
  _id: importedOwnerSelection.projectId,
  organisationId: importedOwnerSelection.organisationId,
});
const selectedProjectIsLogicalDefault = importedOwnerSelection.projectId.equals(
  importedOwnerSelection.organisationId,
);

if (
  importedUsers !== 2
  || importedOwnerUsernames !== 1
  || importedApplicationUsernames !== 1
  || importedOrganisations !== 1
  || importedMemberships !== 1
  || importedProjects !== 1
  || importedSubscriptions !== 1
  || importedSettings !== 5
  || selectedOrganisationExists !== 1
  || (!selectedProjectIsLogicalDefault && selectedProjectExists !== 1)
) {
  throw new Error(
    `Import verification failed: users=${importedUsers}, `
      + `organisations=${importedOrganisations}, memberships=${importedMemberships}, `
      + `projects=${importedProjects}, subscriptions=${importedSubscriptions}, `
      + `settings=${importedSettings}`,
  );
}

print('Imported 2 users, 1 organisation, 1 membership, 1 project, 1 subscription, and 5 settings records into Kerberos.');