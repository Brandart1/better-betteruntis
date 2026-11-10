// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $AccountsTable extends Accounts
    with TableInfo<$AccountsTable, AccountRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AccountsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _schoolIdMeta = const VerificationMeta(
    'schoolId',
  );
  @override
  late final GeneratedColumn<int> schoolId = GeneratedColumn<int>(
    'school_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _schoolLoginNameMeta = const VerificationMeta(
    'schoolLoginName',
  );
  @override
  late final GeneratedColumn<String> schoolLoginName = GeneratedColumn<String>(
    'school_login_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _schoolDisplayNameMeta = const VerificationMeta(
    'schoolDisplayName',
  );
  @override
  late final GeneratedColumn<String> schoolDisplayName =
      GeneratedColumn<String>(
        'school_display_name',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _schoolAddressMeta = const VerificationMeta(
    'schoolAddress',
  );
  @override
  late final GeneratedColumn<String> schoolAddress = GeneratedColumn<String>(
    'school_address',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _schoolHostMeta = const VerificationMeta(
    'schoolHost',
  );
  @override
  late final GeneratedColumn<String> schoolHost = GeneratedColumn<String>(
    'school_host',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _usernameMeta = const VerificationMeta(
    'username',
  );
  @override
  late final GeneratedColumn<String> username = GeneratedColumn<String>(
    'username',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _anonymousMeta = const VerificationMeta(
    'anonymous',
  );
  @override
  late final GeneratedColumn<bool> anonymous = GeneratedColumn<bool>(
    'anonymous',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("anonymous" IN (0, 1))',
    ),
  );
  static const VerificationMeta _displayNameMeta = const VerificationMeta(
    'displayName',
  );
  @override
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
    'display_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _profileNameMeta = const VerificationMeta(
    'profileName',
  );
  @override
  late final GeneratedColumn<String> profileName = GeneratedColumn<String>(
    'profile_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _elementTypeMeta = const VerificationMeta(
    'elementType',
  );
  @override
  late final GeneratedColumn<String> elementType = GeneratedColumn<String>(
    'element_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _elementIdMeta = const VerificationMeta(
    'elementId',
  );
  @override
  late final GeneratedColumn<int> elementId = GeneratedColumn<int>(
    'element_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _klassenIdsJsonMeta = const VerificationMeta(
    'klassenIdsJson',
  );
  @override
  late final GeneratedColumn<String> klassenIdsJson = GeneratedColumn<String>(
    'klassen_ids_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _rightsJsonMeta = const VerificationMeta(
    'rightsJson',
  );
  @override
  late final GeneratedColumn<String> rightsJson = GeneratedColumn<String>(
    'rights_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _masterDataTimestampMeta =
      const VerificationMeta('masterDataTimestamp');
  @override
  late final GeneratedColumn<int> masterDataTimestamp = GeneratedColumn<int>(
    'master_data_timestamp',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _hostOverrideMeta = const VerificationMeta(
    'hostOverride',
  );
  @override
  late final GeneratedColumn<String> hostOverride = GeneratedColumn<String>(
    'host_override',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    position,
    schoolId,
    schoolLoginName,
    schoolDisplayName,
    schoolAddress,
    schoolHost,
    username,
    anonymous,
    displayName,
    profileName,
    elementType,
    elementId,
    klassenIdsJson,
    rightsJson,
    masterDataTimestamp,
    hostOverride,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'accounts';
  @override
  VerificationContext validateIntegrity(
    Insertable<AccountRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMeta);
    }
    if (data.containsKey('school_id')) {
      context.handle(
        _schoolIdMeta,
        schoolId.isAcceptableOrUnknown(data['school_id']!, _schoolIdMeta),
      );
    } else if (isInserting) {
      context.missing(_schoolIdMeta);
    }
    if (data.containsKey('school_login_name')) {
      context.handle(
        _schoolLoginNameMeta,
        schoolLoginName.isAcceptableOrUnknown(
          data['school_login_name']!,
          _schoolLoginNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_schoolLoginNameMeta);
    }
    if (data.containsKey('school_display_name')) {
      context.handle(
        _schoolDisplayNameMeta,
        schoolDisplayName.isAcceptableOrUnknown(
          data['school_display_name']!,
          _schoolDisplayNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_schoolDisplayNameMeta);
    }
    if (data.containsKey('school_address')) {
      context.handle(
        _schoolAddressMeta,
        schoolAddress.isAcceptableOrUnknown(
          data['school_address']!,
          _schoolAddressMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_schoolAddressMeta);
    }
    if (data.containsKey('school_host')) {
      context.handle(
        _schoolHostMeta,
        schoolHost.isAcceptableOrUnknown(data['school_host']!, _schoolHostMeta),
      );
    } else if (isInserting) {
      context.missing(_schoolHostMeta);
    }
    if (data.containsKey('username')) {
      context.handle(
        _usernameMeta,
        username.isAcceptableOrUnknown(data['username']!, _usernameMeta),
      );
    } else if (isInserting) {
      context.missing(_usernameMeta);
    }
    if (data.containsKey('anonymous')) {
      context.handle(
        _anonymousMeta,
        anonymous.isAcceptableOrUnknown(data['anonymous']!, _anonymousMeta),
      );
    } else if (isInserting) {
      context.missing(_anonymousMeta);
    }
    if (data.containsKey('display_name')) {
      context.handle(
        _displayNameMeta,
        displayName.isAcceptableOrUnknown(
          data['display_name']!,
          _displayNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_displayNameMeta);
    }
    if (data.containsKey('profile_name')) {
      context.handle(
        _profileNameMeta,
        profileName.isAcceptableOrUnknown(
          data['profile_name']!,
          _profileNameMeta,
        ),
      );
    }
    if (data.containsKey('element_type')) {
      context.handle(
        _elementTypeMeta,
        elementType.isAcceptableOrUnknown(
          data['element_type']!,
          _elementTypeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_elementTypeMeta);
    }
    if (data.containsKey('element_id')) {
      context.handle(
        _elementIdMeta,
        elementId.isAcceptableOrUnknown(data['element_id']!, _elementIdMeta),
      );
    } else if (isInserting) {
      context.missing(_elementIdMeta);
    }
    if (data.containsKey('klassen_ids_json')) {
      context.handle(
        _klassenIdsJsonMeta,
        klassenIdsJson.isAcceptableOrUnknown(
          data['klassen_ids_json']!,
          _klassenIdsJsonMeta,
        ),
      );
    }
    if (data.containsKey('rights_json')) {
      context.handle(
        _rightsJsonMeta,
        rightsJson.isAcceptableOrUnknown(data['rights_json']!, _rightsJsonMeta),
      );
    }
    if (data.containsKey('master_data_timestamp')) {
      context.handle(
        _masterDataTimestampMeta,
        masterDataTimestamp.isAcceptableOrUnknown(
          data['master_data_timestamp']!,
          _masterDataTimestampMeta,
        ),
      );
    }
    if (data.containsKey('host_override')) {
      context.handle(
        _hostOverrideMeta,
        hostOverride.isAcceptableOrUnknown(
          data['host_override']!,
          _hostOverrideMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AccountRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AccountRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
      schoolId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}school_id'],
      )!,
      schoolLoginName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}school_login_name'],
      )!,
      schoolDisplayName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}school_display_name'],
      )!,
      schoolAddress: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}school_address'],
      )!,
      schoolHost: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}school_host'],
      )!,
      username: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}username'],
      )!,
      anonymous: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}anonymous'],
      )!,
      displayName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display_name'],
      )!,
      profileName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}profile_name'],
      ),
      elementType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}element_type'],
      )!,
      elementId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}element_id'],
      )!,
      klassenIdsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}klassen_ids_json'],
      )!,
      rightsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}rights_json'],
      )!,
      masterDataTimestamp: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}master_data_timestamp'],
      )!,
      hostOverride: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}host_override'],
      ),
    );
  }

  @override
  $AccountsTable createAlias(String alias) {
    return $AccountsTable(attachedDatabase, alias);
  }
}

class AccountRow extends DataClass implements Insertable<AccountRow> {
  final String id;
  final int position;
  final int schoolId;
  final String schoolLoginName;
  final String schoolDisplayName;
  final String schoolAddress;
  final String schoolHost;
  final String username;
  final bool anonymous;
  final String displayName;
  final String? profileName;
  final String elementType;
  final int elementId;
  final String klassenIdsJson;
  final String rightsJson;
  final int masterDataTimestamp;
  final String? hostOverride;
  const AccountRow({
    required this.id,
    required this.position,
    required this.schoolId,
    required this.schoolLoginName,
    required this.schoolDisplayName,
    required this.schoolAddress,
    required this.schoolHost,
    required this.username,
    required this.anonymous,
    required this.displayName,
    this.profileName,
    required this.elementType,
    required this.elementId,
    required this.klassenIdsJson,
    required this.rightsJson,
    required this.masterDataTimestamp,
    this.hostOverride,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['position'] = Variable<int>(position);
    map['school_id'] = Variable<int>(schoolId);
    map['school_login_name'] = Variable<String>(schoolLoginName);
    map['school_display_name'] = Variable<String>(schoolDisplayName);
    map['school_address'] = Variable<String>(schoolAddress);
    map['school_host'] = Variable<String>(schoolHost);
    map['username'] = Variable<String>(username);
    map['anonymous'] = Variable<bool>(anonymous);
    map['display_name'] = Variable<String>(displayName);
    if (!nullToAbsent || profileName != null) {
      map['profile_name'] = Variable<String>(profileName);
    }
    map['element_type'] = Variable<String>(elementType);
    map['element_id'] = Variable<int>(elementId);
    map['klassen_ids_json'] = Variable<String>(klassenIdsJson);
    map['rights_json'] = Variable<String>(rightsJson);
    map['master_data_timestamp'] = Variable<int>(masterDataTimestamp);
    if (!nullToAbsent || hostOverride != null) {
      map['host_override'] = Variable<String>(hostOverride);
    }
    return map;
  }

  AccountsCompanion toCompanion(bool nullToAbsent) {
    return AccountsCompanion(
      id: Value(id),
      position: Value(position),
      schoolId: Value(schoolId),
      schoolLoginName: Value(schoolLoginName),
      schoolDisplayName: Value(schoolDisplayName),
      schoolAddress: Value(schoolAddress),
      schoolHost: Value(schoolHost),
      username: Value(username),
      anonymous: Value(anonymous),
      displayName: Value(displayName),
      profileName: profileName == null && nullToAbsent
          ? const Value.absent()
          : Value(profileName),
      elementType: Value(elementType),
      elementId: Value(elementId),
      klassenIdsJson: Value(klassenIdsJson),
      rightsJson: Value(rightsJson),
      masterDataTimestamp: Value(masterDataTimestamp),
      hostOverride: hostOverride == null && nullToAbsent
          ? const Value.absent()
          : Value(hostOverride),
    );
  }

  factory AccountRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AccountRow(
      id: serializer.fromJson<String>(json['id']),
      position: serializer.fromJson<int>(json['position']),
      schoolId: serializer.fromJson<int>(json['schoolId']),
      schoolLoginName: serializer.fromJson<String>(json['schoolLoginName']),
      schoolDisplayName: serializer.fromJson<String>(json['schoolDisplayName']),
      schoolAddress: serializer.fromJson<String>(json['schoolAddress']),
      schoolHost: serializer.fromJson<String>(json['schoolHost']),
      username: serializer.fromJson<String>(json['username']),
      anonymous: serializer.fromJson<bool>(json['anonymous']),
      displayName: serializer.fromJson<String>(json['displayName']),
      profileName: serializer.fromJson<String?>(json['profileName']),
      elementType: serializer.fromJson<String>(json['elementType']),
      elementId: serializer.fromJson<int>(json['elementId']),
      klassenIdsJson: serializer.fromJson<String>(json['klassenIdsJson']),
      rightsJson: serializer.fromJson<String>(json['rightsJson']),
      masterDataTimestamp: serializer.fromJson<int>(
        json['masterDataTimestamp'],
      ),
      hostOverride: serializer.fromJson<String?>(json['hostOverride']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'position': serializer.toJson<int>(position),
      'schoolId': serializer.toJson<int>(schoolId),
      'schoolLoginName': serializer.toJson<String>(schoolLoginName),
      'schoolDisplayName': serializer.toJson<String>(schoolDisplayName),
      'schoolAddress': serializer.toJson<String>(schoolAddress),
      'schoolHost': serializer.toJson<String>(schoolHost),
      'username': serializer.toJson<String>(username),
      'anonymous': serializer.toJson<bool>(anonymous),
      'displayName': serializer.toJson<String>(displayName),
      'profileName': serializer.toJson<String?>(profileName),
      'elementType': serializer.toJson<String>(elementType),
      'elementId': serializer.toJson<int>(elementId),
      'klassenIdsJson': serializer.toJson<String>(klassenIdsJson),
      'rightsJson': serializer.toJson<String>(rightsJson),
      'masterDataTimestamp': serializer.toJson<int>(masterDataTimestamp),
      'hostOverride': serializer.toJson<String?>(hostOverride),
    };
  }

  AccountRow copyWith({
    String? id,
    int? position,
    int? schoolId,
    String? schoolLoginName,
    String? schoolDisplayName,
    String? schoolAddress,
    String? schoolHost,
    String? username,
    bool? anonymous,
    String? displayName,
    Value<String?> profileName = const Value.absent(),
    String? elementType,
    int? elementId,
    String? klassenIdsJson,
    String? rightsJson,
    int? masterDataTimestamp,
    Value<String?> hostOverride = const Value.absent(),
  }) => AccountRow(
    id: id ?? this.id,
    position: position ?? this.position,
    schoolId: schoolId ?? this.schoolId,
    schoolLoginName: schoolLoginName ?? this.schoolLoginName,
    schoolDisplayName: schoolDisplayName ?? this.schoolDisplayName,
    schoolAddress: schoolAddress ?? this.schoolAddress,
    schoolHost: schoolHost ?? this.schoolHost,
    username: username ?? this.username,
    anonymous: anonymous ?? this.anonymous,
    displayName: displayName ?? this.displayName,
    profileName: profileName.present ? profileName.value : this.profileName,
    elementType: elementType ?? this.elementType,
    elementId: elementId ?? this.elementId,
    klassenIdsJson: klassenIdsJson ?? this.klassenIdsJson,
    rightsJson: rightsJson ?? this.rightsJson,
    masterDataTimestamp: masterDataTimestamp ?? this.masterDataTimestamp,
    hostOverride: hostOverride.present ? hostOverride.value : this.hostOverride,
  );
  AccountRow copyWithCompanion(AccountsCompanion data) {
    return AccountRow(
      id: data.id.present ? data.id.value : this.id,
      position: data.position.present ? data.position.value : this.position,
      schoolId: data.schoolId.present ? data.schoolId.value : this.schoolId,
      schoolLoginName: data.schoolLoginName.present
          ? data.schoolLoginName.value
          : this.schoolLoginName,
      schoolDisplayName: data.schoolDisplayName.present
          ? data.schoolDisplayName.value
          : this.schoolDisplayName,
      schoolAddress: data.schoolAddress.present
          ? data.schoolAddress.value
          : this.schoolAddress,
      schoolHost: data.schoolHost.present
          ? data.schoolHost.value
          : this.schoolHost,
      username: data.username.present ? data.username.value : this.username,
      anonymous: data.anonymous.present ? data.anonymous.value : this.anonymous,
      displayName: data.displayName.present
          ? data.displayName.value
          : this.displayName,
      profileName: data.profileName.present
          ? data.profileName.value
          : this.profileName,
      elementType: data.elementType.present
          ? data.elementType.value
          : this.elementType,
      elementId: data.elementId.present ? data.elementId.value : this.elementId,
      klassenIdsJson: data.klassenIdsJson.present
          ? data.klassenIdsJson.value
          : this.klassenIdsJson,
      rightsJson: data.rightsJson.present
          ? data.rightsJson.value
          : this.rightsJson,
      masterDataTimestamp: data.masterDataTimestamp.present
          ? data.masterDataTimestamp.value
          : this.masterDataTimestamp,
      hostOverride: data.hostOverride.present
          ? data.hostOverride.value
          : this.hostOverride,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AccountRow(')
          ..write('id: $id, ')
          ..write('position: $position, ')
          ..write('schoolId: $schoolId, ')
          ..write('schoolLoginName: $schoolLoginName, ')
          ..write('schoolDisplayName: $schoolDisplayName, ')
          ..write('schoolAddress: $schoolAddress, ')
          ..write('schoolHost: $schoolHost, ')
          ..write('username: $username, ')
          ..write('anonymous: $anonymous, ')
          ..write('displayName: $displayName, ')
          ..write('profileName: $profileName, ')
          ..write('elementType: $elementType, ')
          ..write('elementId: $elementId, ')
          ..write('klassenIdsJson: $klassenIdsJson, ')
          ..write('rightsJson: $rightsJson, ')
          ..write('masterDataTimestamp: $masterDataTimestamp, ')
          ..write('hostOverride: $hostOverride')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    position,
    schoolId,
    schoolLoginName,
    schoolDisplayName,
    schoolAddress,
    schoolHost,
    username,
    anonymous,
    displayName,
    profileName,
    elementType,
    elementId,
    klassenIdsJson,
    rightsJson,
    masterDataTimestamp,
    hostOverride,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AccountRow &&
          other.id == this.id &&
          other.position == this.position &&
          other.schoolId == this.schoolId &&
          other.schoolLoginName == this.schoolLoginName &&
          other.schoolDisplayName == this.schoolDisplayName &&
          other.schoolAddress == this.schoolAddress &&
          other.schoolHost == this.schoolHost &&
          other.username == this.username &&
          other.anonymous == this.anonymous &&
          other.displayName == this.displayName &&
          other.profileName == this.profileName &&
          other.elementType == this.elementType &&
          other.elementId == this.elementId &&
          other.klassenIdsJson == this.klassenIdsJson &&
          other.rightsJson == this.rightsJson &&
          other.masterDataTimestamp == this.masterDataTimestamp &&
          other.hostOverride == this.hostOverride);
}

class AccountsCompanion extends UpdateCompanion<AccountRow> {
  final Value<String> id;
  final Value<int> position;
  final Value<int> schoolId;
  final Value<String> schoolLoginName;
  final Value<String> schoolDisplayName;
  final Value<String> schoolAddress;
  final Value<String> schoolHost;
  final Value<String> username;
  final Value<bool> anonymous;
  final Value<String> displayName;
  final Value<String?> profileName;
  final Value<String> elementType;
  final Value<int> elementId;
  final Value<String> klassenIdsJson;
  final Value<String> rightsJson;
  final Value<int> masterDataTimestamp;
  final Value<String?> hostOverride;
  final Value<int> rowid;
  const AccountsCompanion({
    this.id = const Value.absent(),
    this.position = const Value.absent(),
    this.schoolId = const Value.absent(),
    this.schoolLoginName = const Value.absent(),
    this.schoolDisplayName = const Value.absent(),
    this.schoolAddress = const Value.absent(),
    this.schoolHost = const Value.absent(),
    this.username = const Value.absent(),
    this.anonymous = const Value.absent(),
    this.displayName = const Value.absent(),
    this.profileName = const Value.absent(),
    this.elementType = const Value.absent(),
    this.elementId = const Value.absent(),
    this.klassenIdsJson = const Value.absent(),
    this.rightsJson = const Value.absent(),
    this.masterDataTimestamp = const Value.absent(),
    this.hostOverride = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AccountsCompanion.insert({
    required String id,
    required int position,
    required int schoolId,
    required String schoolLoginName,
    required String schoolDisplayName,
    required String schoolAddress,
    required String schoolHost,
    required String username,
    required bool anonymous,
    required String displayName,
    this.profileName = const Value.absent(),
    required String elementType,
    required int elementId,
    this.klassenIdsJson = const Value.absent(),
    this.rightsJson = const Value.absent(),
    this.masterDataTimestamp = const Value.absent(),
    this.hostOverride = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       position = Value(position),
       schoolId = Value(schoolId),
       schoolLoginName = Value(schoolLoginName),
       schoolDisplayName = Value(schoolDisplayName),
       schoolAddress = Value(schoolAddress),
       schoolHost = Value(schoolHost),
       username = Value(username),
       anonymous = Value(anonymous),
       displayName = Value(displayName),
       elementType = Value(elementType),
       elementId = Value(elementId);
  static Insertable<AccountRow> custom({
    Expression<String>? id,
    Expression<int>? position,
    Expression<int>? schoolId,
    Expression<String>? schoolLoginName,
    Expression<String>? schoolDisplayName,
    Expression<String>? schoolAddress,
    Expression<String>? schoolHost,
    Expression<String>? username,
    Expression<bool>? anonymous,
    Expression<String>? displayName,
    Expression<String>? profileName,
    Expression<String>? elementType,
    Expression<int>? elementId,
    Expression<String>? klassenIdsJson,
    Expression<String>? rightsJson,
    Expression<int>? masterDataTimestamp,
    Expression<String>? hostOverride,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (position != null) 'position': position,
      if (schoolId != null) 'school_id': schoolId,
      if (schoolLoginName != null) 'school_login_name': schoolLoginName,
      if (schoolDisplayName != null) 'school_display_name': schoolDisplayName,
      if (schoolAddress != null) 'school_address': schoolAddress,
      if (schoolHost != null) 'school_host': schoolHost,
      if (username != null) 'username': username,
      if (anonymous != null) 'anonymous': anonymous,
      if (displayName != null) 'display_name': displayName,
      if (profileName != null) 'profile_name': profileName,
      if (elementType != null) 'element_type': elementType,
      if (elementId != null) 'element_id': elementId,
      if (klassenIdsJson != null) 'klassen_ids_json': klassenIdsJson,
      if (rightsJson != null) 'rights_json': rightsJson,
      if (masterDataTimestamp != null)
        'master_data_timestamp': masterDataTimestamp,
      if (hostOverride != null) 'host_override': hostOverride,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AccountsCompanion copyWith({
    Value<String>? id,
    Value<int>? position,
    Value<int>? schoolId,
    Value<String>? schoolLoginName,
    Value<String>? schoolDisplayName,
    Value<String>? schoolAddress,
    Value<String>? schoolHost,
    Value<String>? username,
    Value<bool>? anonymous,
    Value<String>? displayName,
    Value<String?>? profileName,
    Value<String>? elementType,
    Value<int>? elementId,
    Value<String>? klassenIdsJson,
    Value<String>? rightsJson,
    Value<int>? masterDataTimestamp,
    Value<String?>? hostOverride,
    Value<int>? rowid,
  }) {
    return AccountsCompanion(
      id: id ?? this.id,
      position: position ?? this.position,
      schoolId: schoolId ?? this.schoolId,
      schoolLoginName: schoolLoginName ?? this.schoolLoginName,
      schoolDisplayName: schoolDisplayName ?? this.schoolDisplayName,
      schoolAddress: schoolAddress ?? this.schoolAddress,
      schoolHost: schoolHost ?? this.schoolHost,
      username: username ?? this.username,
      anonymous: anonymous ?? this.anonymous,
      displayName: displayName ?? this.displayName,
      profileName: profileName ?? this.profileName,
      elementType: elementType ?? this.elementType,
      elementId: elementId ?? this.elementId,
      klassenIdsJson: klassenIdsJson ?? this.klassenIdsJson,
      rightsJson: rightsJson ?? this.rightsJson,
      masterDataTimestamp: masterDataTimestamp ?? this.masterDataTimestamp,
      hostOverride: hostOverride ?? this.hostOverride,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (schoolId.present) {
      map['school_id'] = Variable<int>(schoolId.value);
    }
    if (schoolLoginName.present) {
      map['school_login_name'] = Variable<String>(schoolLoginName.value);
    }
    if (schoolDisplayName.present) {
      map['school_display_name'] = Variable<String>(schoolDisplayName.value);
    }
    if (schoolAddress.present) {
      map['school_address'] = Variable<String>(schoolAddress.value);
    }
    if (schoolHost.present) {
      map['school_host'] = Variable<String>(schoolHost.value);
    }
    if (username.present) {
      map['username'] = Variable<String>(username.value);
    }
    if (anonymous.present) {
      map['anonymous'] = Variable<bool>(anonymous.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (profileName.present) {
      map['profile_name'] = Variable<String>(profileName.value);
    }
    if (elementType.present) {
      map['element_type'] = Variable<String>(elementType.value);
    }
    if (elementId.present) {
      map['element_id'] = Variable<int>(elementId.value);
    }
    if (klassenIdsJson.present) {
      map['klassen_ids_json'] = Variable<String>(klassenIdsJson.value);
    }
    if (rightsJson.present) {
      map['rights_json'] = Variable<String>(rightsJson.value);
    }
    if (masterDataTimestamp.present) {
      map['master_data_timestamp'] = Variable<int>(masterDataTimestamp.value);
    }
    if (hostOverride.present) {
      map['host_override'] = Variable<String>(hostOverride.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AccountsCompanion(')
          ..write('id: $id, ')
          ..write('position: $position, ')
          ..write('schoolId: $schoolId, ')
          ..write('schoolLoginName: $schoolLoginName, ')
          ..write('schoolDisplayName: $schoolDisplayName, ')
          ..write('schoolAddress: $schoolAddress, ')
          ..write('schoolHost: $schoolHost, ')
          ..write('username: $username, ')
          ..write('anonymous: $anonymous, ')
          ..write('displayName: $displayName, ')
          ..write('profileName: $profileName, ')
          ..write('elementType: $elementType, ')
          ..write('elementId: $elementId, ')
          ..write('klassenIdsJson: $klassenIdsJson, ')
          ..write('rightsJson: $rightsJson, ')
          ..write('masterDataTimestamp: $masterDataTimestamp, ')
          ..write('hostOverride: $hostOverride, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MasterElementsTable extends MasterElements
    with TableInfo<$MasterElementsTable, MasterElementRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MasterElementsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _accountIdMeta = const VerificationMeta(
    'accountId',
  );
  @override
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
    'account_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _longNameMeta = const VerificationMeta(
    'longName',
  );
  @override
  late final GeneratedColumn<String> longName = GeneratedColumn<String>(
    'long_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _foreColorMeta = const VerificationMeta(
    'foreColor',
  );
  @override
  late final GeneratedColumn<int> foreColor = GeneratedColumn<int>(
    'fore_color',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _backColorMeta = const VerificationMeta(
    'backColor',
  );
  @override
  late final GeneratedColumn<int> backColor = GeneratedColumn<int>(
    'back_color',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _activeMeta = const VerificationMeta('active');
  @override
  late final GeneratedColumn<bool> active = GeneratedColumn<bool>(
    'active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("active" IN (0, 1))',
    ),
  );
  static const VerificationMeta _displayAllowedMeta = const VerificationMeta(
    'displayAllowed',
  );
  @override
  late final GeneratedColumn<bool> displayAllowed = GeneratedColumn<bool>(
    'display_allowed',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("display_allowed" IN (0, 1))',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [
    accountId,
    type,
    id,
    name,
    longName,
    foreColor,
    backColor,
    active,
    displayAllowed,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'master_elements';
  @override
  VerificationContext validateIntegrity(
    Insertable<MasterElementRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('account_id')) {
      context.handle(
        _accountIdMeta,
        accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta),
      );
    } else if (isInserting) {
      context.missing(_accountIdMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('long_name')) {
      context.handle(
        _longNameMeta,
        longName.isAcceptableOrUnknown(data['long_name']!, _longNameMeta),
      );
    } else if (isInserting) {
      context.missing(_longNameMeta);
    }
    if (data.containsKey('fore_color')) {
      context.handle(
        _foreColorMeta,
        foreColor.isAcceptableOrUnknown(data['fore_color']!, _foreColorMeta),
      );
    }
    if (data.containsKey('back_color')) {
      context.handle(
        _backColorMeta,
        backColor.isAcceptableOrUnknown(data['back_color']!, _backColorMeta),
      );
    }
    if (data.containsKey('active')) {
      context.handle(
        _activeMeta,
        active.isAcceptableOrUnknown(data['active']!, _activeMeta),
      );
    } else if (isInserting) {
      context.missing(_activeMeta);
    }
    if (data.containsKey('display_allowed')) {
      context.handle(
        _displayAllowedMeta,
        displayAllowed.isAcceptableOrUnknown(
          data['display_allowed']!,
          _displayAllowedMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_displayAllowedMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {accountId, type, id};
  @override
  MasterElementRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MasterElementRow(
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_id'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      longName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}long_name'],
      )!,
      foreColor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}fore_color'],
      ),
      backColor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}back_color'],
      ),
      active: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}active'],
      )!,
      displayAllowed: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}display_allowed'],
      )!,
    );
  }

  @override
  $MasterElementsTable createAlias(String alias) {
    return $MasterElementsTable(attachedDatabase, alias);
  }
}

class MasterElementRow extends DataClass
    implements Insertable<MasterElementRow> {
  final String accountId;
  final String type;
  final int id;
  final String name;
  final String longName;
  final int? foreColor;
  final int? backColor;
  final bool active;
  final bool displayAllowed;
  const MasterElementRow({
    required this.accountId,
    required this.type,
    required this.id,
    required this.name,
    required this.longName,
    this.foreColor,
    this.backColor,
    required this.active,
    required this.displayAllowed,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['account_id'] = Variable<String>(accountId);
    map['type'] = Variable<String>(type);
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['long_name'] = Variable<String>(longName);
    if (!nullToAbsent || foreColor != null) {
      map['fore_color'] = Variable<int>(foreColor);
    }
    if (!nullToAbsent || backColor != null) {
      map['back_color'] = Variable<int>(backColor);
    }
    map['active'] = Variable<bool>(active);
    map['display_allowed'] = Variable<bool>(displayAllowed);
    return map;
  }

  MasterElementsCompanion toCompanion(bool nullToAbsent) {
    return MasterElementsCompanion(
      accountId: Value(accountId),
      type: Value(type),
      id: Value(id),
      name: Value(name),
      longName: Value(longName),
      foreColor: foreColor == null && nullToAbsent
          ? const Value.absent()
          : Value(foreColor),
      backColor: backColor == null && nullToAbsent
          ? const Value.absent()
          : Value(backColor),
      active: Value(active),
      displayAllowed: Value(displayAllowed),
    );
  }

  factory MasterElementRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MasterElementRow(
      accountId: serializer.fromJson<String>(json['accountId']),
      type: serializer.fromJson<String>(json['type']),
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      longName: serializer.fromJson<String>(json['longName']),
      foreColor: serializer.fromJson<int?>(json['foreColor']),
      backColor: serializer.fromJson<int?>(json['backColor']),
      active: serializer.fromJson<bool>(json['active']),
      displayAllowed: serializer.fromJson<bool>(json['displayAllowed']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'accountId': serializer.toJson<String>(accountId),
      'type': serializer.toJson<String>(type),
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'longName': serializer.toJson<String>(longName),
      'foreColor': serializer.toJson<int?>(foreColor),
      'backColor': serializer.toJson<int?>(backColor),
      'active': serializer.toJson<bool>(active),
      'displayAllowed': serializer.toJson<bool>(displayAllowed),
    };
  }

  MasterElementRow copyWith({
    String? accountId,
    String? type,
    int? id,
    String? name,
    String? longName,
    Value<int?> foreColor = const Value.absent(),
    Value<int?> backColor = const Value.absent(),
    bool? active,
    bool? displayAllowed,
  }) => MasterElementRow(
    accountId: accountId ?? this.accountId,
    type: type ?? this.type,
    id: id ?? this.id,
    name: name ?? this.name,
    longName: longName ?? this.longName,
    foreColor: foreColor.present ? foreColor.value : this.foreColor,
    backColor: backColor.present ? backColor.value : this.backColor,
    active: active ?? this.active,
    displayAllowed: displayAllowed ?? this.displayAllowed,
  );
  MasterElementRow copyWithCompanion(MasterElementsCompanion data) {
    return MasterElementRow(
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      type: data.type.present ? data.type.value : this.type,
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      longName: data.longName.present ? data.longName.value : this.longName,
      foreColor: data.foreColor.present ? data.foreColor.value : this.foreColor,
      backColor: data.backColor.present ? data.backColor.value : this.backColor,
      active: data.active.present ? data.active.value : this.active,
      displayAllowed: data.displayAllowed.present
          ? data.displayAllowed.value
          : this.displayAllowed,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MasterElementRow(')
          ..write('accountId: $accountId, ')
          ..write('type: $type, ')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('longName: $longName, ')
          ..write('foreColor: $foreColor, ')
          ..write('backColor: $backColor, ')
          ..write('active: $active, ')
          ..write('displayAllowed: $displayAllowed')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    accountId,
    type,
    id,
    name,
    longName,
    foreColor,
    backColor,
    active,
    displayAllowed,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MasterElementRow &&
          other.accountId == this.accountId &&
          other.type == this.type &&
          other.id == this.id &&
          other.name == this.name &&
          other.longName == this.longName &&
          other.foreColor == this.foreColor &&
          other.backColor == this.backColor &&
          other.active == this.active &&
          other.displayAllowed == this.displayAllowed);
}

class MasterElementsCompanion extends UpdateCompanion<MasterElementRow> {
  final Value<String> accountId;
  final Value<String> type;
  final Value<int> id;
  final Value<String> name;
  final Value<String> longName;
  final Value<int?> foreColor;
  final Value<int?> backColor;
  final Value<bool> active;
  final Value<bool> displayAllowed;
  final Value<int> rowid;
  const MasterElementsCompanion({
    this.accountId = const Value.absent(),
    this.type = const Value.absent(),
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.longName = const Value.absent(),
    this.foreColor = const Value.absent(),
    this.backColor = const Value.absent(),
    this.active = const Value.absent(),
    this.displayAllowed = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MasterElementsCompanion.insert({
    required String accountId,
    required String type,
    required int id,
    required String name,
    required String longName,
    this.foreColor = const Value.absent(),
    this.backColor = const Value.absent(),
    required bool active,
    required bool displayAllowed,
    this.rowid = const Value.absent(),
  }) : accountId = Value(accountId),
       type = Value(type),
       id = Value(id),
       name = Value(name),
       longName = Value(longName),
       active = Value(active),
       displayAllowed = Value(displayAllowed);
  static Insertable<MasterElementRow> custom({
    Expression<String>? accountId,
    Expression<String>? type,
    Expression<int>? id,
    Expression<String>? name,
    Expression<String>? longName,
    Expression<int>? foreColor,
    Expression<int>? backColor,
    Expression<bool>? active,
    Expression<bool>? displayAllowed,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (accountId != null) 'account_id': accountId,
      if (type != null) 'type': type,
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (longName != null) 'long_name': longName,
      if (foreColor != null) 'fore_color': foreColor,
      if (backColor != null) 'back_color': backColor,
      if (active != null) 'active': active,
      if (displayAllowed != null) 'display_allowed': displayAllowed,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MasterElementsCompanion copyWith({
    Value<String>? accountId,
    Value<String>? type,
    Value<int>? id,
    Value<String>? name,
    Value<String>? longName,
    Value<int?>? foreColor,
    Value<int?>? backColor,
    Value<bool>? active,
    Value<bool>? displayAllowed,
    Value<int>? rowid,
  }) {
    return MasterElementsCompanion(
      accountId: accountId ?? this.accountId,
      type: type ?? this.type,
      id: id ?? this.id,
      name: name ?? this.name,
      longName: longName ?? this.longName,
      foreColor: foreColor ?? this.foreColor,
      backColor: backColor ?? this.backColor,
      active: active ?? this.active,
      displayAllowed: displayAllowed ?? this.displayAllowed,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (longName.present) {
      map['long_name'] = Variable<String>(longName.value);
    }
    if (foreColor.present) {
      map['fore_color'] = Variable<int>(foreColor.value);
    }
    if (backColor.present) {
      map['back_color'] = Variable<int>(backColor.value);
    }
    if (active.present) {
      map['active'] = Variable<bool>(active.value);
    }
    if (displayAllowed.present) {
      map['display_allowed'] = Variable<bool>(displayAllowed.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MasterElementsCompanion(')
          ..write('accountId: $accountId, ')
          ..write('type: $type, ')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('longName: $longName, ')
          ..write('foreColor: $foreColor, ')
          ..write('backColor: $backColor, ')
          ..write('active: $active, ')
          ..write('displayAllowed: $displayAllowed, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $HolidaysTable extends Holidays
    with TableInfo<$HolidaysTable, HolidayRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $HolidaysTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _accountIdMeta = const VerificationMeta(
    'accountId',
  );
  @override
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
    'account_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _longNameMeta = const VerificationMeta(
    'longName',
  );
  @override
  late final GeneratedColumn<String> longName = GeneratedColumn<String>(
    'long_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startDateMeta = const VerificationMeta(
    'startDate',
  );
  @override
  late final GeneratedColumn<String> startDate = GeneratedColumn<String>(
    'start_date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endDateMeta = const VerificationMeta(
    'endDate',
  );
  @override
  late final GeneratedColumn<String> endDate = GeneratedColumn<String>(
    'end_date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    accountId,
    id,
    name,
    longName,
    startDate,
    endDate,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'holidays';
  @override
  VerificationContext validateIntegrity(
    Insertable<HolidayRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('account_id')) {
      context.handle(
        _accountIdMeta,
        accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta),
      );
    } else if (isInserting) {
      context.missing(_accountIdMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('long_name')) {
      context.handle(
        _longNameMeta,
        longName.isAcceptableOrUnknown(data['long_name']!, _longNameMeta),
      );
    } else if (isInserting) {
      context.missing(_longNameMeta);
    }
    if (data.containsKey('start_date')) {
      context.handle(
        _startDateMeta,
        startDate.isAcceptableOrUnknown(data['start_date']!, _startDateMeta),
      );
    } else if (isInserting) {
      context.missing(_startDateMeta);
    }
    if (data.containsKey('end_date')) {
      context.handle(
        _endDateMeta,
        endDate.isAcceptableOrUnknown(data['end_date']!, _endDateMeta),
      );
    } else if (isInserting) {
      context.missing(_endDateMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {accountId, id};
  @override
  HolidayRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return HolidayRow(
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_id'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      longName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}long_name'],
      )!,
      startDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}start_date'],
      )!,
      endDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}end_date'],
      )!,
    );
  }

  @override
  $HolidaysTable createAlias(String alias) {
    return $HolidaysTable(attachedDatabase, alias);
  }
}

class HolidayRow extends DataClass implements Insertable<HolidayRow> {
  final String accountId;
  final int id;
  final String name;
  final String longName;
  final String startDate;
  final String endDate;
  const HolidayRow({
    required this.accountId,
    required this.id,
    required this.name,
    required this.longName,
    required this.startDate,
    required this.endDate,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['account_id'] = Variable<String>(accountId);
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['long_name'] = Variable<String>(longName);
    map['start_date'] = Variable<String>(startDate);
    map['end_date'] = Variable<String>(endDate);
    return map;
  }

  HolidaysCompanion toCompanion(bool nullToAbsent) {
    return HolidaysCompanion(
      accountId: Value(accountId),
      id: Value(id),
      name: Value(name),
      longName: Value(longName),
      startDate: Value(startDate),
      endDate: Value(endDate),
    );
  }

  factory HolidayRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return HolidayRow(
      accountId: serializer.fromJson<String>(json['accountId']),
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      longName: serializer.fromJson<String>(json['longName']),
      startDate: serializer.fromJson<String>(json['startDate']),
      endDate: serializer.fromJson<String>(json['endDate']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'accountId': serializer.toJson<String>(accountId),
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'longName': serializer.toJson<String>(longName),
      'startDate': serializer.toJson<String>(startDate),
      'endDate': serializer.toJson<String>(endDate),
    };
  }

  HolidayRow copyWith({
    String? accountId,
    int? id,
    String? name,
    String? longName,
    String? startDate,
    String? endDate,
  }) => HolidayRow(
    accountId: accountId ?? this.accountId,
    id: id ?? this.id,
    name: name ?? this.name,
    longName: longName ?? this.longName,
    startDate: startDate ?? this.startDate,
    endDate: endDate ?? this.endDate,
  );
  HolidayRow copyWithCompanion(HolidaysCompanion data) {
    return HolidayRow(
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      longName: data.longName.present ? data.longName.value : this.longName,
      startDate: data.startDate.present ? data.startDate.value : this.startDate,
      endDate: data.endDate.present ? data.endDate.value : this.endDate,
    );
  }

  @override
  String toString() {
    return (StringBuffer('HolidayRow(')
          ..write('accountId: $accountId, ')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('longName: $longName, ')
          ..write('startDate: $startDate, ')
          ..write('endDate: $endDate')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(accountId, id, name, longName, startDate, endDate);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HolidayRow &&
          other.accountId == this.accountId &&
          other.id == this.id &&
          other.name == this.name &&
          other.longName == this.longName &&
          other.startDate == this.startDate &&
          other.endDate == this.endDate);
}

class HolidaysCompanion extends UpdateCompanion<HolidayRow> {
  final Value<String> accountId;
  final Value<int> id;
  final Value<String> name;
  final Value<String> longName;
  final Value<String> startDate;
  final Value<String> endDate;
  final Value<int> rowid;
  const HolidaysCompanion({
    this.accountId = const Value.absent(),
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.longName = const Value.absent(),
    this.startDate = const Value.absent(),
    this.endDate = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  HolidaysCompanion.insert({
    required String accountId,
    required int id,
    required String name,
    required String longName,
    required String startDate,
    required String endDate,
    this.rowid = const Value.absent(),
  }) : accountId = Value(accountId),
       id = Value(id),
       name = Value(name),
       longName = Value(longName),
       startDate = Value(startDate),
       endDate = Value(endDate);
  static Insertable<HolidayRow> custom({
    Expression<String>? accountId,
    Expression<int>? id,
    Expression<String>? name,
    Expression<String>? longName,
    Expression<String>? startDate,
    Expression<String>? endDate,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (accountId != null) 'account_id': accountId,
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (longName != null) 'long_name': longName,
      if (startDate != null) 'start_date': startDate,
      if (endDate != null) 'end_date': endDate,
      if (rowid != null) 'rowid': rowid,
    });
  }

  HolidaysCompanion copyWith({
    Value<String>? accountId,
    Value<int>? id,
    Value<String>? name,
    Value<String>? longName,
    Value<String>? startDate,
    Value<String>? endDate,
    Value<int>? rowid,
  }) {
    return HolidaysCompanion(
      accountId: accountId ?? this.accountId,
      id: id ?? this.id,
      name: name ?? this.name,
      longName: longName ?? this.longName,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (longName.present) {
      map['long_name'] = Variable<String>(longName.value);
    }
    if (startDate.present) {
      map['start_date'] = Variable<String>(startDate.value);
    }
    if (endDate.present) {
      map['end_date'] = Variable<String>(endDate.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('HolidaysCompanion(')
          ..write('accountId: $accountId, ')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('longName: $longName, ')
          ..write('startDate: $startDate, ')
          ..write('endDate: $endDate, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SchoolYearsTable extends SchoolYears
    with TableInfo<$SchoolYearsTable, SchoolYearRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SchoolYearsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _accountIdMeta = const VerificationMeta(
    'accountId',
  );
  @override
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
    'account_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startDateMeta = const VerificationMeta(
    'startDate',
  );
  @override
  late final GeneratedColumn<String> startDate = GeneratedColumn<String>(
    'start_date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endDateMeta = const VerificationMeta(
    'endDate',
  );
  @override
  late final GeneratedColumn<String> endDate = GeneratedColumn<String>(
    'end_date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    accountId,
    id,
    name,
    startDate,
    endDate,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'school_years';
  @override
  VerificationContext validateIntegrity(
    Insertable<SchoolYearRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('account_id')) {
      context.handle(
        _accountIdMeta,
        accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta),
      );
    } else if (isInserting) {
      context.missing(_accountIdMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('start_date')) {
      context.handle(
        _startDateMeta,
        startDate.isAcceptableOrUnknown(data['start_date']!, _startDateMeta),
      );
    } else if (isInserting) {
      context.missing(_startDateMeta);
    }
    if (data.containsKey('end_date')) {
      context.handle(
        _endDateMeta,
        endDate.isAcceptableOrUnknown(data['end_date']!, _endDateMeta),
      );
    } else if (isInserting) {
      context.missing(_endDateMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {accountId, id};
  @override
  SchoolYearRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SchoolYearRow(
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_id'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      startDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}start_date'],
      )!,
      endDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}end_date'],
      )!,
    );
  }

  @override
  $SchoolYearsTable createAlias(String alias) {
    return $SchoolYearsTable(attachedDatabase, alias);
  }
}

class SchoolYearRow extends DataClass implements Insertable<SchoolYearRow> {
  final String accountId;
  final int id;
  final String name;
  final String startDate;
  final String endDate;
  const SchoolYearRow({
    required this.accountId,
    required this.id,
    required this.name,
    required this.startDate,
    required this.endDate,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['account_id'] = Variable<String>(accountId);
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['start_date'] = Variable<String>(startDate);
    map['end_date'] = Variable<String>(endDate);
    return map;
  }

  SchoolYearsCompanion toCompanion(bool nullToAbsent) {
    return SchoolYearsCompanion(
      accountId: Value(accountId),
      id: Value(id),
      name: Value(name),
      startDate: Value(startDate),
      endDate: Value(endDate),
    );
  }

  factory SchoolYearRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SchoolYearRow(
      accountId: serializer.fromJson<String>(json['accountId']),
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      startDate: serializer.fromJson<String>(json['startDate']),
      endDate: serializer.fromJson<String>(json['endDate']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'accountId': serializer.toJson<String>(accountId),
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'startDate': serializer.toJson<String>(startDate),
      'endDate': serializer.toJson<String>(endDate),
    };
  }

  SchoolYearRow copyWith({
    String? accountId,
    int? id,
    String? name,
    String? startDate,
    String? endDate,
  }) => SchoolYearRow(
    accountId: accountId ?? this.accountId,
    id: id ?? this.id,
    name: name ?? this.name,
    startDate: startDate ?? this.startDate,
    endDate: endDate ?? this.endDate,
  );
  SchoolYearRow copyWithCompanion(SchoolYearsCompanion data) {
    return SchoolYearRow(
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      startDate: data.startDate.present ? data.startDate.value : this.startDate,
      endDate: data.endDate.present ? data.endDate.value : this.endDate,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SchoolYearRow(')
          ..write('accountId: $accountId, ')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('startDate: $startDate, ')
          ..write('endDate: $endDate')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(accountId, id, name, startDate, endDate);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SchoolYearRow &&
          other.accountId == this.accountId &&
          other.id == this.id &&
          other.name == this.name &&
          other.startDate == this.startDate &&
          other.endDate == this.endDate);
}

class SchoolYearsCompanion extends UpdateCompanion<SchoolYearRow> {
  final Value<String> accountId;
  final Value<int> id;
  final Value<String> name;
  final Value<String> startDate;
  final Value<String> endDate;
  final Value<int> rowid;
  const SchoolYearsCompanion({
    this.accountId = const Value.absent(),
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.startDate = const Value.absent(),
    this.endDate = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SchoolYearsCompanion.insert({
    required String accountId,
    required int id,
    required String name,
    required String startDate,
    required String endDate,
    this.rowid = const Value.absent(),
  }) : accountId = Value(accountId),
       id = Value(id),
       name = Value(name),
       startDate = Value(startDate),
       endDate = Value(endDate);
  static Insertable<SchoolYearRow> custom({
    Expression<String>? accountId,
    Expression<int>? id,
    Expression<String>? name,
    Expression<String>? startDate,
    Expression<String>? endDate,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (accountId != null) 'account_id': accountId,
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (startDate != null) 'start_date': startDate,
      if (endDate != null) 'end_date': endDate,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SchoolYearsCompanion copyWith({
    Value<String>? accountId,
    Value<int>? id,
    Value<String>? name,
    Value<String>? startDate,
    Value<String>? endDate,
    Value<int>? rowid,
  }) {
    return SchoolYearsCompanion(
      accountId: accountId ?? this.accountId,
      id: id ?? this.id,
      name: name ?? this.name,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (startDate.present) {
      map['start_date'] = Variable<String>(startDate.value);
    }
    if (endDate.present) {
      map['end_date'] = Variable<String>(endDate.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SchoolYearsCompanion(')
          ..write('accountId: $accountId, ')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('startDate: $startDate, ')
          ..write('endDate: $endDate, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TimeGridsTable extends TimeGrids
    with TableInfo<$TimeGridsTable, TimeGridRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TimeGridsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _accountIdMeta = const VerificationMeta(
    'accountId',
  );
  @override
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
    'account_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _jsonMeta = const VerificationMeta('json');
  @override
  late final GeneratedColumn<String> json = GeneratedColumn<String>(
    'json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [accountId, json];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'time_grids';
  @override
  VerificationContext validateIntegrity(
    Insertable<TimeGridRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('account_id')) {
      context.handle(
        _accountIdMeta,
        accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta),
      );
    } else if (isInserting) {
      context.missing(_accountIdMeta);
    }
    if (data.containsKey('json')) {
      context.handle(
        _jsonMeta,
        json.isAcceptableOrUnknown(data['json']!, _jsonMeta),
      );
    } else if (isInserting) {
      context.missing(_jsonMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {accountId};
  @override
  TimeGridRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TimeGridRow(
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_id'],
      )!,
      json: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}json'],
      )!,
    );
  }

  @override
  $TimeGridsTable createAlias(String alias) {
    return $TimeGridsTable(attachedDatabase, alias);
  }
}

class TimeGridRow extends DataClass implements Insertable<TimeGridRow> {
  final String accountId;
  final String json;
  const TimeGridRow({required this.accountId, required this.json});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['account_id'] = Variable<String>(accountId);
    map['json'] = Variable<String>(json);
    return map;
  }

  TimeGridsCompanion toCompanion(bool nullToAbsent) {
    return TimeGridsCompanion(accountId: Value(accountId), json: Value(json));
  }

  factory TimeGridRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TimeGridRow(
      accountId: serializer.fromJson<String>(json['accountId']),
      json: serializer.fromJson<String>(json['json']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'accountId': serializer.toJson<String>(accountId),
      'json': serializer.toJson<String>(json),
    };
  }

  TimeGridRow copyWith({String? accountId, String? json}) => TimeGridRow(
    accountId: accountId ?? this.accountId,
    json: json ?? this.json,
  );
  TimeGridRow copyWithCompanion(TimeGridsCompanion data) {
    return TimeGridRow(
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      json: data.json.present ? data.json.value : this.json,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TimeGridRow(')
          ..write('accountId: $accountId, ')
          ..write('json: $json')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(accountId, json);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TimeGridRow &&
          other.accountId == this.accountId &&
          other.json == this.json);
}

class TimeGridsCompanion extends UpdateCompanion<TimeGridRow> {
  final Value<String> accountId;
  final Value<String> json;
  final Value<int> rowid;
  const TimeGridsCompanion({
    this.accountId = const Value.absent(),
    this.json = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TimeGridsCompanion.insert({
    required String accountId,
    required String json,
    this.rowid = const Value.absent(),
  }) : accountId = Value(accountId),
       json = Value(json);
  static Insertable<TimeGridRow> custom({
    Expression<String>? accountId,
    Expression<String>? json,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (accountId != null) 'account_id': accountId,
      if (json != null) 'json': json,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TimeGridsCompanion copyWith({
    Value<String>? accountId,
    Value<String>? json,
    Value<int>? rowid,
  }) {
    return TimeGridsCompanion(
      accountId: accountId ?? this.accountId,
      json: json ?? this.json,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (json.present) {
      map['json'] = Variable<String>(json.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TimeGridsCompanion(')
          ..write('accountId: $accountId, ')
          ..write('json: $json, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedWeeksTable extends CachedWeeks
    with TableInfo<$CachedWeeksTable, CachedWeekRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedWeeksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _accountIdMeta = const VerificationMeta(
    'accountId',
  );
  @override
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
    'account_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _targetTypeMeta = const VerificationMeta(
    'targetType',
  );
  @override
  late final GeneratedColumn<String> targetType = GeneratedColumn<String>(
    'target_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _targetIdMeta = const VerificationMeta(
    'targetId',
  );
  @override
  late final GeneratedColumn<int> targetId = GeneratedColumn<int>(
    'target_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _weekStartMeta = const VerificationMeta(
    'weekStart',
  );
  @override
  late final GeneratedColumn<String> weekStart = GeneratedColumn<String>(
    'week_start',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _periodsJsonMeta = const VerificationMeta(
    'periodsJson',
  );
  @override
  late final GeneratedColumn<String> periodsJson = GeneratedColumn<String>(
    'periods_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fetchedAtMeta = const VerificationMeta(
    'fetchedAt',
  );
  @override
  late final GeneratedColumn<int> fetchedAt = GeneratedColumn<int>(
    'fetched_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    accountId,
    targetType,
    targetId,
    weekStart,
    periodsJson,
    fetchedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_weeks';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedWeekRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('account_id')) {
      context.handle(
        _accountIdMeta,
        accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta),
      );
    } else if (isInserting) {
      context.missing(_accountIdMeta);
    }
    if (data.containsKey('target_type')) {
      context.handle(
        _targetTypeMeta,
        targetType.isAcceptableOrUnknown(data['target_type']!, _targetTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_targetTypeMeta);
    }
    if (data.containsKey('target_id')) {
      context.handle(
        _targetIdMeta,
        targetId.isAcceptableOrUnknown(data['target_id']!, _targetIdMeta),
      );
    } else if (isInserting) {
      context.missing(_targetIdMeta);
    }
    if (data.containsKey('week_start')) {
      context.handle(
        _weekStartMeta,
        weekStart.isAcceptableOrUnknown(data['week_start']!, _weekStartMeta),
      );
    } else if (isInserting) {
      context.missing(_weekStartMeta);
    }
    if (data.containsKey('periods_json')) {
      context.handle(
        _periodsJsonMeta,
        periodsJson.isAcceptableOrUnknown(
          data['periods_json']!,
          _periodsJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_periodsJsonMeta);
    }
    if (data.containsKey('fetched_at')) {
      context.handle(
        _fetchedAtMeta,
        fetchedAt.isAcceptableOrUnknown(data['fetched_at']!, _fetchedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_fetchedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {
    accountId,
    targetType,
    targetId,
    weekStart,
  };
  @override
  CachedWeekRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedWeekRow(
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_id'],
      )!,
      targetType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}target_type'],
      )!,
      targetId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}target_id'],
      )!,
      weekStart: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}week_start'],
      )!,
      periodsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}periods_json'],
      )!,
      fetchedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}fetched_at'],
      )!,
    );
  }

  @override
  $CachedWeeksTable createAlias(String alias) {
    return $CachedWeeksTable(attachedDatabase, alias);
  }
}

class CachedWeekRow extends DataClass implements Insertable<CachedWeekRow> {
  final String accountId;
  final String targetType;
  final int targetId;
  final String weekStart;
  final String periodsJson;

  /// Milliseconds since epoch (UTC).
  final int fetchedAt;
  const CachedWeekRow({
    required this.accountId,
    required this.targetType,
    required this.targetId,
    required this.weekStart,
    required this.periodsJson,
    required this.fetchedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['account_id'] = Variable<String>(accountId);
    map['target_type'] = Variable<String>(targetType);
    map['target_id'] = Variable<int>(targetId);
    map['week_start'] = Variable<String>(weekStart);
    map['periods_json'] = Variable<String>(periodsJson);
    map['fetched_at'] = Variable<int>(fetchedAt);
    return map;
  }

  CachedWeeksCompanion toCompanion(bool nullToAbsent) {
    return CachedWeeksCompanion(
      accountId: Value(accountId),
      targetType: Value(targetType),
      targetId: Value(targetId),
      weekStart: Value(weekStart),
      periodsJson: Value(periodsJson),
      fetchedAt: Value(fetchedAt),
    );
  }

  factory CachedWeekRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedWeekRow(
      accountId: serializer.fromJson<String>(json['accountId']),
      targetType: serializer.fromJson<String>(json['targetType']),
      targetId: serializer.fromJson<int>(json['targetId']),
      weekStart: serializer.fromJson<String>(json['weekStart']),
      periodsJson: serializer.fromJson<String>(json['periodsJson']),
      fetchedAt: serializer.fromJson<int>(json['fetchedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'accountId': serializer.toJson<String>(accountId),
      'targetType': serializer.toJson<String>(targetType),
      'targetId': serializer.toJson<int>(targetId),
      'weekStart': serializer.toJson<String>(weekStart),
      'periodsJson': serializer.toJson<String>(periodsJson),
      'fetchedAt': serializer.toJson<int>(fetchedAt),
    };
  }

  CachedWeekRow copyWith({
    String? accountId,
    String? targetType,
    int? targetId,
    String? weekStart,
    String? periodsJson,
    int? fetchedAt,
  }) => CachedWeekRow(
    accountId: accountId ?? this.accountId,
    targetType: targetType ?? this.targetType,
    targetId: targetId ?? this.targetId,
    weekStart: weekStart ?? this.weekStart,
    periodsJson: periodsJson ?? this.periodsJson,
    fetchedAt: fetchedAt ?? this.fetchedAt,
  );
  CachedWeekRow copyWithCompanion(CachedWeeksCompanion data) {
    return CachedWeekRow(
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      targetType: data.targetType.present
          ? data.targetType.value
          : this.targetType,
      targetId: data.targetId.present ? data.targetId.value : this.targetId,
      weekStart: data.weekStart.present ? data.weekStart.value : this.weekStart,
      periodsJson: data.periodsJson.present
          ? data.periodsJson.value
          : this.periodsJson,
      fetchedAt: data.fetchedAt.present ? data.fetchedAt.value : this.fetchedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedWeekRow(')
          ..write('accountId: $accountId, ')
          ..write('targetType: $targetType, ')
          ..write('targetId: $targetId, ')
          ..write('weekStart: $weekStart, ')
          ..write('periodsJson: $periodsJson, ')
          ..write('fetchedAt: $fetchedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    accountId,
    targetType,
    targetId,
    weekStart,
    periodsJson,
    fetchedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedWeekRow &&
          other.accountId == this.accountId &&
          other.targetType == this.targetType &&
          other.targetId == this.targetId &&
          other.weekStart == this.weekStart &&
          other.periodsJson == this.periodsJson &&
          other.fetchedAt == this.fetchedAt);
}

class CachedWeeksCompanion extends UpdateCompanion<CachedWeekRow> {
  final Value<String> accountId;
  final Value<String> targetType;
  final Value<int> targetId;
  final Value<String> weekStart;
  final Value<String> periodsJson;
  final Value<int> fetchedAt;
  final Value<int> rowid;
  const CachedWeeksCompanion({
    this.accountId = const Value.absent(),
    this.targetType = const Value.absent(),
    this.targetId = const Value.absent(),
    this.weekStart = const Value.absent(),
    this.periodsJson = const Value.absent(),
    this.fetchedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedWeeksCompanion.insert({
    required String accountId,
    required String targetType,
    required int targetId,
    required String weekStart,
    required String periodsJson,
    required int fetchedAt,
    this.rowid = const Value.absent(),
  }) : accountId = Value(accountId),
       targetType = Value(targetType),
       targetId = Value(targetId),
       weekStart = Value(weekStart),
       periodsJson = Value(periodsJson),
       fetchedAt = Value(fetchedAt);
  static Insertable<CachedWeekRow> custom({
    Expression<String>? accountId,
    Expression<String>? targetType,
    Expression<int>? targetId,
    Expression<String>? weekStart,
    Expression<String>? periodsJson,
    Expression<int>? fetchedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (accountId != null) 'account_id': accountId,
      if (targetType != null) 'target_type': targetType,
      if (targetId != null) 'target_id': targetId,
      if (weekStart != null) 'week_start': weekStart,
      if (periodsJson != null) 'periods_json': periodsJson,
      if (fetchedAt != null) 'fetched_at': fetchedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedWeeksCompanion copyWith({
    Value<String>? accountId,
    Value<String>? targetType,
    Value<int>? targetId,
    Value<String>? weekStart,
    Value<String>? periodsJson,
    Value<int>? fetchedAt,
    Value<int>? rowid,
  }) {
    return CachedWeeksCompanion(
      accountId: accountId ?? this.accountId,
      targetType: targetType ?? this.targetType,
      targetId: targetId ?? this.targetId,
      weekStart: weekStart ?? this.weekStart,
      periodsJson: periodsJson ?? this.periodsJson,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (targetType.present) {
      map['target_type'] = Variable<String>(targetType.value);
    }
    if (targetId.present) {
      map['target_id'] = Variable<int>(targetId.value);
    }
    if (weekStart.present) {
      map['week_start'] = Variable<String>(weekStart.value);
    }
    if (periodsJson.present) {
      map['periods_json'] = Variable<String>(periodsJson.value);
    }
    if (fetchedAt.present) {
      map['fetched_at'] = Variable<int>(fetchedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedWeeksCompanion(')
          ..write('accountId: $accountId, ')
          ..write('targetType: $targetType, ')
          ..write('targetId: $targetId, ')
          ..write('weekStart: $weekStart, ')
          ..write('periodsJson: $periodsJson, ')
          ..write('fetchedAt: $fetchedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AppStateTable extends AppState
    with TableInfo<$AppStateTable, AppStateRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AppStateTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'app_state';
  @override
  VerificationContext validateIntegrity(
    Insertable<AppStateRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  AppStateRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AppStateRow(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      ),
    );
  }

  @override
  $AppStateTable createAlias(String alias) {
    return $AppStateTable(attachedDatabase, alias);
  }
}

class AppStateRow extends DataClass implements Insertable<AppStateRow> {
  final String key;
  final String? value;
  const AppStateRow({required this.key, this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    if (!nullToAbsent || value != null) {
      map['value'] = Variable<String>(value);
    }
    return map;
  }

  AppStateCompanion toCompanion(bool nullToAbsent) {
    return AppStateCompanion(
      key: Value(key),
      value: value == null && nullToAbsent
          ? const Value.absent()
          : Value(value),
    );
  }

  factory AppStateRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AppStateRow(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String?>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String?>(value),
    };
  }

  AppStateRow copyWith({
    String? key,
    Value<String?> value = const Value.absent(),
  }) => AppStateRow(
    key: key ?? this.key,
    value: value.present ? value.value : this.value,
  );
  AppStateRow copyWithCompanion(AppStateCompanion data) {
    return AppStateRow(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AppStateRow(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AppStateRow &&
          other.key == this.key &&
          other.value == this.value);
}

class AppStateCompanion extends UpdateCompanion<AppStateRow> {
  final Value<String> key;
  final Value<String?> value;
  final Value<int> rowid;
  const AppStateCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AppStateCompanion.insert({
    required String key,
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : key = Value(key);
  static Insertable<AppStateRow> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AppStateCompanion copyWith({
    Value<String>? key,
    Value<String?>? value,
    Value<int>? rowid,
  }) {
    return AppStateCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AppStateCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $InfoCacheTable extends InfoCache
    with TableInfo<$InfoCacheTable, InfoCacheRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $InfoCacheTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _accountIdMeta = const VerificationMeta(
    'accountId',
  );
  @override
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
    'account_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _jsonMeta = const VerificationMeta('json');
  @override
  late final GeneratedColumn<String> json = GeneratedColumn<String>(
    'json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fetchedAtMeta = const VerificationMeta(
    'fetchedAt',
  );
  @override
  late final GeneratedColumn<int> fetchedAt = GeneratedColumn<int>(
    'fetched_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [accountId, key, json, fetchedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'info_cache';
  @override
  VerificationContext validateIntegrity(
    Insertable<InfoCacheRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('account_id')) {
      context.handle(
        _accountIdMeta,
        accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta),
      );
    } else if (isInserting) {
      context.missing(_accountIdMeta);
    }
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('json')) {
      context.handle(
        _jsonMeta,
        json.isAcceptableOrUnknown(data['json']!, _jsonMeta),
      );
    } else if (isInserting) {
      context.missing(_jsonMeta);
    }
    if (data.containsKey('fetched_at')) {
      context.handle(
        _fetchedAtMeta,
        fetchedAt.isAcceptableOrUnknown(data['fetched_at']!, _fetchedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_fetchedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {accountId, key};
  @override
  InfoCacheRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return InfoCacheRow(
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_id'],
      )!,
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      json: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}json'],
      )!,
      fetchedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}fetched_at'],
      )!,
    );
  }

  @override
  $InfoCacheTable createAlias(String alias) {
    return $InfoCacheTable(attachedDatabase, alias);
  }
}

class InfoCacheRow extends DataClass implements Insertable<InfoCacheRow> {
  final String accountId;
  final String key;
  final String json;

  /// Milliseconds since epoch (UTC).
  final int fetchedAt;
  const InfoCacheRow({
    required this.accountId,
    required this.key,
    required this.json,
    required this.fetchedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['account_id'] = Variable<String>(accountId);
    map['key'] = Variable<String>(key);
    map['json'] = Variable<String>(json);
    map['fetched_at'] = Variable<int>(fetchedAt);
    return map;
  }

  InfoCacheCompanion toCompanion(bool nullToAbsent) {
    return InfoCacheCompanion(
      accountId: Value(accountId),
      key: Value(key),
      json: Value(json),
      fetchedAt: Value(fetchedAt),
    );
  }

  factory InfoCacheRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return InfoCacheRow(
      accountId: serializer.fromJson<String>(json['accountId']),
      key: serializer.fromJson<String>(json['key']),
      json: serializer.fromJson<String>(json['json']),
      fetchedAt: serializer.fromJson<int>(json['fetchedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'accountId': serializer.toJson<String>(accountId),
      'key': serializer.toJson<String>(key),
      'json': serializer.toJson<String>(json),
      'fetchedAt': serializer.toJson<int>(fetchedAt),
    };
  }

  InfoCacheRow copyWith({
    String? accountId,
    String? key,
    String? json,
    int? fetchedAt,
  }) => InfoCacheRow(
    accountId: accountId ?? this.accountId,
    key: key ?? this.key,
    json: json ?? this.json,
    fetchedAt: fetchedAt ?? this.fetchedAt,
  );
  InfoCacheRow copyWithCompanion(InfoCacheCompanion data) {
    return InfoCacheRow(
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      key: data.key.present ? data.key.value : this.key,
      json: data.json.present ? data.json.value : this.json,
      fetchedAt: data.fetchedAt.present ? data.fetchedAt.value : this.fetchedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('InfoCacheRow(')
          ..write('accountId: $accountId, ')
          ..write('key: $key, ')
          ..write('json: $json, ')
          ..write('fetchedAt: $fetchedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(accountId, key, json, fetchedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is InfoCacheRow &&
          other.accountId == this.accountId &&
          other.key == this.key &&
          other.json == this.json &&
          other.fetchedAt == this.fetchedAt);
}

class InfoCacheCompanion extends UpdateCompanion<InfoCacheRow> {
  final Value<String> accountId;
  final Value<String> key;
  final Value<String> json;
  final Value<int> fetchedAt;
  final Value<int> rowid;
  const InfoCacheCompanion({
    this.accountId = const Value.absent(),
    this.key = const Value.absent(),
    this.json = const Value.absent(),
    this.fetchedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  InfoCacheCompanion.insert({
    required String accountId,
    required String key,
    required String json,
    required int fetchedAt,
    this.rowid = const Value.absent(),
  }) : accountId = Value(accountId),
       key = Value(key),
       json = Value(json),
       fetchedAt = Value(fetchedAt);
  static Insertable<InfoCacheRow> custom({
    Expression<String>? accountId,
    Expression<String>? key,
    Expression<String>? json,
    Expression<int>? fetchedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (accountId != null) 'account_id': accountId,
      if (key != null) 'key': key,
      if (json != null) 'json': json,
      if (fetchedAt != null) 'fetched_at': fetchedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  InfoCacheCompanion copyWith({
    Value<String>? accountId,
    Value<String>? key,
    Value<String>? json,
    Value<int>? fetchedAt,
    Value<int>? rowid,
  }) {
    return InfoCacheCompanion(
      accountId: accountId ?? this.accountId,
      key: key ?? this.key,
      json: json ?? this.json,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (json.present) {
      map['json'] = Variable<String>(json.value);
    }
    if (fetchedAt.present) {
      map['fetched_at'] = Variable<int>(fetchedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('InfoCacheCompanion(')
          ..write('accountId: $accountId, ')
          ..write('key: $key, ')
          ..write('json: $json, ')
          ..write('fetchedAt: $fetchedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AbsenceLookupEntriesTable extends AbsenceLookupEntries
    with TableInfo<$AbsenceLookupEntriesTable, AbsenceLookupRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AbsenceLookupEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _accountIdMeta = const VerificationMeta(
    'accountId',
  );
  @override
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
    'account_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [accountId, kind, id, name];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'absence_lookup_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<AbsenceLookupRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('account_id')) {
      context.handle(
        _accountIdMeta,
        accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta),
      );
    } else if (isInserting) {
      context.missing(_accountIdMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {accountId, kind, id};
  @override
  AbsenceLookupRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AbsenceLookupRow(
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
    );
  }

  @override
  $AbsenceLookupEntriesTable createAlias(String alias) {
    return $AbsenceLookupEntriesTable(attachedDatabase, alias);
  }
}

class AbsenceLookupRow extends DataClass
    implements Insertable<AbsenceLookupRow> {
  final String accountId;
  final String kind;
  final int id;
  final String name;
  const AbsenceLookupRow({
    required this.accountId,
    required this.kind,
    required this.id,
    required this.name,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['account_id'] = Variable<String>(accountId);
    map['kind'] = Variable<String>(kind);
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    return map;
  }

  AbsenceLookupEntriesCompanion toCompanion(bool nullToAbsent) {
    return AbsenceLookupEntriesCompanion(
      accountId: Value(accountId),
      kind: Value(kind),
      id: Value(id),
      name: Value(name),
    );
  }

  factory AbsenceLookupRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AbsenceLookupRow(
      accountId: serializer.fromJson<String>(json['accountId']),
      kind: serializer.fromJson<String>(json['kind']),
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'accountId': serializer.toJson<String>(accountId),
      'kind': serializer.toJson<String>(kind),
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
    };
  }

  AbsenceLookupRow copyWith({
    String? accountId,
    String? kind,
    int? id,
    String? name,
  }) => AbsenceLookupRow(
    accountId: accountId ?? this.accountId,
    kind: kind ?? this.kind,
    id: id ?? this.id,
    name: name ?? this.name,
  );
  AbsenceLookupRow copyWithCompanion(AbsenceLookupEntriesCompanion data) {
    return AbsenceLookupRow(
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      kind: data.kind.present ? data.kind.value : this.kind,
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AbsenceLookupRow(')
          ..write('accountId: $accountId, ')
          ..write('kind: $kind, ')
          ..write('id: $id, ')
          ..write('name: $name')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(accountId, kind, id, name);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AbsenceLookupRow &&
          other.accountId == this.accountId &&
          other.kind == this.kind &&
          other.id == this.id &&
          other.name == this.name);
}

class AbsenceLookupEntriesCompanion extends UpdateCompanion<AbsenceLookupRow> {
  final Value<String> accountId;
  final Value<String> kind;
  final Value<int> id;
  final Value<String> name;
  final Value<int> rowid;
  const AbsenceLookupEntriesCompanion({
    this.accountId = const Value.absent(),
    this.kind = const Value.absent(),
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AbsenceLookupEntriesCompanion.insert({
    required String accountId,
    required String kind,
    required int id,
    required String name,
    this.rowid = const Value.absent(),
  }) : accountId = Value(accountId),
       kind = Value(kind),
       id = Value(id),
       name = Value(name);
  static Insertable<AbsenceLookupRow> custom({
    Expression<String>? accountId,
    Expression<String>? kind,
    Expression<int>? id,
    Expression<String>? name,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (accountId != null) 'account_id': accountId,
      if (kind != null) 'kind': kind,
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AbsenceLookupEntriesCompanion copyWith({
    Value<String>? accountId,
    Value<String>? kind,
    Value<int>? id,
    Value<String>? name,
    Value<int>? rowid,
  }) {
    return AbsenceLookupEntriesCompanion(
      accountId: accountId ?? this.accountId,
      kind: kind ?? this.kind,
      id: id ?? this.id,
      name: name ?? this.name,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AbsenceLookupEntriesCompanion(')
          ..write('accountId: $accountId, ')
          ..write('kind: $kind, ')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $AccountsTable accounts = $AccountsTable(this);
  late final $MasterElementsTable masterElements = $MasterElementsTable(this);
  late final $HolidaysTable holidays = $HolidaysTable(this);
  late final $SchoolYearsTable schoolYears = $SchoolYearsTable(this);
  late final $TimeGridsTable timeGrids = $TimeGridsTable(this);
  late final $CachedWeeksTable cachedWeeks = $CachedWeeksTable(this);
  late final $AppStateTable appState = $AppStateTable(this);
  late final $InfoCacheTable infoCache = $InfoCacheTable(this);
  late final $AbsenceLookupEntriesTable absenceLookupEntries =
      $AbsenceLookupEntriesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    accounts,
    masterElements,
    holidays,
    schoolYears,
    timeGrids,
    cachedWeeks,
    appState,
    infoCache,
    absenceLookupEntries,
  ];
}

typedef $$AccountsTableCreateCompanionBuilder = AccountsCompanion Function({
  required String id,
  required int position,
  required int schoolId,
  required String schoolLoginName,
  required String schoolDisplayName,
  required String schoolAddress,
  required String schoolHost,
  required String username,
  required bool anonymous,
  required String displayName,
  Value<String?> profileName,
  required String elementType,
  required int elementId,
  Value<String> klassenIdsJson,
  Value<String> rightsJson,
  Value<int> masterDataTimestamp,
  Value<String?> hostOverride,
  Value<int> rowid,
});
typedef $$AccountsTableUpdateCompanionBuilder = AccountsCompanion Function({
  Value<String> id,
  Value<int> position,
  Value<int> schoolId,
  Value<String> schoolLoginName,
  Value<String> schoolDisplayName,
  Value<String> schoolAddress,
  Value<String> schoolHost,
  Value<String> username,
  Value<bool> anonymous,
  Value<String> displayName,
  Value<String?> profileName,
  Value<String> elementType,
  Value<int> elementId,
  Value<String> klassenIdsJson,
  Value<String> rightsJson,
  Value<int> masterDataTimestamp,
  Value<String?> hostOverride,
  Value<int> rowid,
});

class $$AccountsTableFilterComposer
    extends Composer<_$AppDatabase, $AccountsTable> {
  $$AccountsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get schoolId => $composableBuilder(
    column: $table.schoolId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get schoolLoginName => $composableBuilder(
    column: $table.schoolLoginName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get schoolDisplayName => $composableBuilder(
    column: $table.schoolDisplayName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get schoolAddress => $composableBuilder(
    column: $table.schoolAddress,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get schoolHost => $composableBuilder(
    column: $table.schoolHost,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get anonymous => $composableBuilder(
    column: $table.anonymous,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get profileName => $composableBuilder(
    column: $table.profileName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get elementType => $composableBuilder(
    column: $table.elementType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get elementId => $composableBuilder(
    column: $table.elementId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get klassenIdsJson => $composableBuilder(
    column: $table.klassenIdsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rightsJson => $composableBuilder(
    column: $table.rightsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get masterDataTimestamp => $composableBuilder(
    column: $table.masterDataTimestamp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hostOverride => $composableBuilder(
    column: $table.hostOverride,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AccountsTableOrderingComposer
    extends Composer<_$AppDatabase, $AccountsTable> {
  $$AccountsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get schoolId => $composableBuilder(
    column: $table.schoolId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get schoolLoginName => $composableBuilder(
    column: $table.schoolLoginName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get schoolDisplayName => $composableBuilder(
    column: $table.schoolDisplayName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get schoolAddress => $composableBuilder(
    column: $table.schoolAddress,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get schoolHost => $composableBuilder(
    column: $table.schoolHost,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get anonymous => $composableBuilder(
    column: $table.anonymous,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get profileName => $composableBuilder(
    column: $table.profileName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get elementType => $composableBuilder(
    column: $table.elementType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get elementId => $composableBuilder(
    column: $table.elementId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get klassenIdsJson => $composableBuilder(
    column: $table.klassenIdsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rightsJson => $composableBuilder(
    column: $table.rightsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get masterDataTimestamp => $composableBuilder(
    column: $table.masterDataTimestamp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hostOverride => $composableBuilder(
    column: $table.hostOverride,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AccountsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AccountsTable> {
  $$AccountsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<int> get schoolId =>
      $composableBuilder(column: $table.schoolId, builder: (column) => column);

  GeneratedColumn<String> get schoolLoginName => $composableBuilder(
    column: $table.schoolLoginName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get schoolDisplayName => $composableBuilder(
    column: $table.schoolDisplayName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get schoolAddress => $composableBuilder(
    column: $table.schoolAddress,
    builder: (column) => column,
  );

  GeneratedColumn<String> get schoolHost => $composableBuilder(
    column: $table.schoolHost,
    builder: (column) => column,
  );

  GeneratedColumn<String> get username =>
      $composableBuilder(column: $table.username, builder: (column) => column);

  GeneratedColumn<bool> get anonymous =>
      $composableBuilder(column: $table.anonymous, builder: (column) => column);

  GeneratedColumn<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get profileName => $composableBuilder(
    column: $table.profileName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get elementType => $composableBuilder(
    column: $table.elementType,
    builder: (column) => column,
  );

  GeneratedColumn<int> get elementId =>
      $composableBuilder(column: $table.elementId, builder: (column) => column);

  GeneratedColumn<String> get klassenIdsJson => $composableBuilder(
    column: $table.klassenIdsJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get rightsJson => $composableBuilder(
    column: $table.rightsJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get masterDataTimestamp => $composableBuilder(
    column: $table.masterDataTimestamp,
    builder: (column) => column,
  );

  GeneratedColumn<String> get hostOverride => $composableBuilder(
    column: $table.hostOverride,
    builder: (column) => column,
  );
}

class $$AccountsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AccountsTable,
          AccountRow,
          $$AccountsTableFilterComposer,
          $$AccountsTableOrderingComposer,
          $$AccountsTableAnnotationComposer,
          $$AccountsTableCreateCompanionBuilder,
          $$AccountsTableUpdateCompanionBuilder,
          (
            AccountRow,
            BaseReferences<_$AppDatabase, $AccountsTable, AccountRow>,
          ),
          AccountRow,
          PrefetchHooks Function()
        > {
  $$AccountsTableTableManager(_$AppDatabase db, $AccountsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AccountsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AccountsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AccountsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<int> schoolId = const Value.absent(),
                Value<String> schoolLoginName = const Value.absent(),
                Value<String> schoolDisplayName = const Value.absent(),
                Value<String> schoolAddress = const Value.absent(),
                Value<String> schoolHost = const Value.absent(),
                Value<String> username = const Value.absent(),
                Value<bool> anonymous = const Value.absent(),
                Value<String> displayName = const Value.absent(),
                Value<String?> profileName = const Value.absent(),
                Value<String> elementType = const Value.absent(),
                Value<int> elementId = const Value.absent(),
                Value<String> klassenIdsJson = const Value.absent(),
                Value<String> rightsJson = const Value.absent(),
                Value<int> masterDataTimestamp = const Value.absent(),
                Value<String?> hostOverride = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AccountsCompanion(
                id: id,
                position: position,
                schoolId: schoolId,
                schoolLoginName: schoolLoginName,
                schoolDisplayName: schoolDisplayName,
                schoolAddress: schoolAddress,
                schoolHost: schoolHost,
                username: username,
                anonymous: anonymous,
                displayName: displayName,
                profileName: profileName,
                elementType: elementType,
                elementId: elementId,
                klassenIdsJson: klassenIdsJson,
                rightsJson: rightsJson,
                masterDataTimestamp: masterDataTimestamp,
                hostOverride: hostOverride,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required int position,
                required int schoolId,
                required String schoolLoginName,
                required String schoolDisplayName,
                required String schoolAddress,
                required String schoolHost,
                required String username,
                required bool anonymous,
                required String displayName,
                Value<String?> profileName = const Value.absent(),
                required String elementType,
                required int elementId,
                Value<String> klassenIdsJson = const Value.absent(),
                Value<String> rightsJson = const Value.absent(),
                Value<int> masterDataTimestamp = const Value.absent(),
                Value<String?> hostOverride = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AccountsCompanion.insert(
                id: id,
                position: position,
                schoolId: schoolId,
                schoolLoginName: schoolLoginName,
                schoolDisplayName: schoolDisplayName,
                schoolAddress: schoolAddress,
                schoolHost: schoolHost,
                username: username,
                anonymous: anonymous,
                displayName: displayName,
                profileName: profileName,
                elementType: elementType,
                elementId: elementId,
                klassenIdsJson: klassenIdsJson,
                rightsJson: rightsJson,
                masterDataTimestamp: masterDataTimestamp,
                hostOverride: hostOverride,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$AccountsTable, AccountRow>(table),
                  BaseReferences<_$AppDatabase, $AccountsTable, AccountRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AccountsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AccountsTable,
      AccountRow,
      $$AccountsTableFilterComposer,
      $$AccountsTableOrderingComposer,
      $$AccountsTableAnnotationComposer,
      $$AccountsTableCreateCompanionBuilder,
      $$AccountsTableUpdateCompanionBuilder,
      (AccountRow, BaseReferences<_$AppDatabase, $AccountsTable, AccountRow>),
      AccountRow,
      PrefetchHooks Function()
    >;
typedef $$MasterElementsTableCreateCompanionBuilder =
    MasterElementsCompanion Function({
      required String accountId,
      required String type,
      required int id,
      required String name,
      required String longName,
      Value<int?> foreColor,
      Value<int?> backColor,
      required bool active,
      required bool displayAllowed,
      Value<int> rowid,
    });
typedef $$MasterElementsTableUpdateCompanionBuilder =
    MasterElementsCompanion Function({
      Value<String> accountId,
      Value<String> type,
      Value<int> id,
      Value<String> name,
      Value<String> longName,
      Value<int?> foreColor,
      Value<int?> backColor,
      Value<bool> active,
      Value<bool> displayAllowed,
      Value<int> rowid,
    });

class $$MasterElementsTableFilterComposer
    extends Composer<_$AppDatabase, $MasterElementsTable> {
  $$MasterElementsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get longName => $composableBuilder(
    column: $table.longName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get foreColor => $composableBuilder(
    column: $table.foreColor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get backColor => $composableBuilder(
    column: $table.backColor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get active => $composableBuilder(
    column: $table.active,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get displayAllowed => $composableBuilder(
    column: $table.displayAllowed,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MasterElementsTableOrderingComposer
    extends Composer<_$AppDatabase, $MasterElementsTable> {
  $$MasterElementsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get longName => $composableBuilder(
    column: $table.longName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get foreColor => $composableBuilder(
    column: $table.foreColor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get backColor => $composableBuilder(
    column: $table.backColor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get active => $composableBuilder(
    column: $table.active,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get displayAllowed => $composableBuilder(
    column: $table.displayAllowed,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MasterElementsTableAnnotationComposer
    extends Composer<_$AppDatabase, $MasterElementsTable> {
  $$MasterElementsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get accountId =>
      $composableBuilder(column: $table.accountId, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get longName =>
      $composableBuilder(column: $table.longName, builder: (column) => column);

  GeneratedColumn<int> get foreColor =>
      $composableBuilder(column: $table.foreColor, builder: (column) => column);

  GeneratedColumn<int> get backColor =>
      $composableBuilder(column: $table.backColor, builder: (column) => column);

  GeneratedColumn<bool> get active =>
      $composableBuilder(column: $table.active, builder: (column) => column);

  GeneratedColumn<bool> get displayAllowed => $composableBuilder(
    column: $table.displayAllowed,
    builder: (column) => column,
  );
}

class $$MasterElementsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MasterElementsTable,
          MasterElementRow,
          $$MasterElementsTableFilterComposer,
          $$MasterElementsTableOrderingComposer,
          $$MasterElementsTableAnnotationComposer,
          $$MasterElementsTableCreateCompanionBuilder,
          $$MasterElementsTableUpdateCompanionBuilder,
          (
            MasterElementRow,
            BaseReferences<
              _$AppDatabase,
              $MasterElementsTable,
              MasterElementRow
            >,
          ),
          MasterElementRow,
          PrefetchHooks Function()
        > {
  $$MasterElementsTableTableManager(
    _$AppDatabase db,
    $MasterElementsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MasterElementsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MasterElementsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MasterElementsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> accountId = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> longName = const Value.absent(),
                Value<int?> foreColor = const Value.absent(),
                Value<int?> backColor = const Value.absent(),
                Value<bool> active = const Value.absent(),
                Value<bool> displayAllowed = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MasterElementsCompanion(
                accountId: accountId,
                type: type,
                id: id,
                name: name,
                longName: longName,
                foreColor: foreColor,
                backColor: backColor,
                active: active,
                displayAllowed: displayAllowed,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String accountId,
                required String type,
                required int id,
                required String name,
                required String longName,
                Value<int?> foreColor = const Value.absent(),
                Value<int?> backColor = const Value.absent(),
                required bool active,
                required bool displayAllowed,
                Value<int> rowid = const Value.absent(),
              }) => MasterElementsCompanion.insert(
                accountId: accountId,
                type: type,
                id: id,
                name: name,
                longName: longName,
                foreColor: foreColor,
                backColor: backColor,
                active: active,
                displayAllowed: displayAllowed,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$MasterElementsTable, MasterElementRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $MasterElementsTable,
                    MasterElementRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MasterElementsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MasterElementsTable,
      MasterElementRow,
      $$MasterElementsTableFilterComposer,
      $$MasterElementsTableOrderingComposer,
      $$MasterElementsTableAnnotationComposer,
      $$MasterElementsTableCreateCompanionBuilder,
      $$MasterElementsTableUpdateCompanionBuilder,
      (
        MasterElementRow,
        BaseReferences<_$AppDatabase, $MasterElementsTable, MasterElementRow>,
      ),
      MasterElementRow,
      PrefetchHooks Function()
    >;
typedef $$HolidaysTableCreateCompanionBuilder = HolidaysCompanion Function({
  required String accountId,
  required int id,
  required String name,
  required String longName,
  required String startDate,
  required String endDate,
  Value<int> rowid,
});
typedef $$HolidaysTableUpdateCompanionBuilder = HolidaysCompanion Function({
  Value<String> accountId,
  Value<int> id,
  Value<String> name,
  Value<String> longName,
  Value<String> startDate,
  Value<String> endDate,
  Value<int> rowid,
});

class $$HolidaysTableFilterComposer
    extends Composer<_$AppDatabase, $HolidaysTable> {
  $$HolidaysTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get longName => $composableBuilder(
    column: $table.longName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get startDate => $composableBuilder(
    column: $table.startDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get endDate => $composableBuilder(
    column: $table.endDate,
    builder: (column) => ColumnFilters(column),
  );
}

class $$HolidaysTableOrderingComposer
    extends Composer<_$AppDatabase, $HolidaysTable> {
  $$HolidaysTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get longName => $composableBuilder(
    column: $table.longName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get startDate => $composableBuilder(
    column: $table.startDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get endDate => $composableBuilder(
    column: $table.endDate,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$HolidaysTableAnnotationComposer
    extends Composer<_$AppDatabase, $HolidaysTable> {
  $$HolidaysTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get accountId =>
      $composableBuilder(column: $table.accountId, builder: (column) => column);

  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get longName =>
      $composableBuilder(column: $table.longName, builder: (column) => column);

  GeneratedColumn<String> get startDate =>
      $composableBuilder(column: $table.startDate, builder: (column) => column);

  GeneratedColumn<String> get endDate =>
      $composableBuilder(column: $table.endDate, builder: (column) => column);
}

class $$HolidaysTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $HolidaysTable,
          HolidayRow,
          $$HolidaysTableFilterComposer,
          $$HolidaysTableOrderingComposer,
          $$HolidaysTableAnnotationComposer,
          $$HolidaysTableCreateCompanionBuilder,
          $$HolidaysTableUpdateCompanionBuilder,
          (
            HolidayRow,
            BaseReferences<_$AppDatabase, $HolidaysTable, HolidayRow>,
          ),
          HolidayRow,
          PrefetchHooks Function()
        > {
  $$HolidaysTableTableManager(_$AppDatabase db, $HolidaysTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$HolidaysTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$HolidaysTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$HolidaysTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> accountId = const Value.absent(),
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> longName = const Value.absent(),
                Value<String> startDate = const Value.absent(),
                Value<String> endDate = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => HolidaysCompanion(
                accountId: accountId,
                id: id,
                name: name,
                longName: longName,
                startDate: startDate,
                endDate: endDate,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String accountId,
                required int id,
                required String name,
                required String longName,
                required String startDate,
                required String endDate,
                Value<int> rowid = const Value.absent(),
              }) => HolidaysCompanion.insert(
                accountId: accountId,
                id: id,
                name: name,
                longName: longName,
                startDate: startDate,
                endDate: endDate,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$HolidaysTable, HolidayRow>(table),
                  BaseReferences<_$AppDatabase, $HolidaysTable, HolidayRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$HolidaysTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $HolidaysTable,
      HolidayRow,
      $$HolidaysTableFilterComposer,
      $$HolidaysTableOrderingComposer,
      $$HolidaysTableAnnotationComposer,
      $$HolidaysTableCreateCompanionBuilder,
      $$HolidaysTableUpdateCompanionBuilder,
      (HolidayRow, BaseReferences<_$AppDatabase, $HolidaysTable, HolidayRow>),
      HolidayRow,
      PrefetchHooks Function()
    >;
typedef $$SchoolYearsTableCreateCompanionBuilder =
    SchoolYearsCompanion Function({
      required String accountId,
      required int id,
      required String name,
      required String startDate,
      required String endDate,
      Value<int> rowid,
    });
typedef $$SchoolYearsTableUpdateCompanionBuilder =
    SchoolYearsCompanion Function({
      Value<String> accountId,
      Value<int> id,
      Value<String> name,
      Value<String> startDate,
      Value<String> endDate,
      Value<int> rowid,
    });

class $$SchoolYearsTableFilterComposer
    extends Composer<_$AppDatabase, $SchoolYearsTable> {
  $$SchoolYearsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get startDate => $composableBuilder(
    column: $table.startDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get endDate => $composableBuilder(
    column: $table.endDate,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SchoolYearsTableOrderingComposer
    extends Composer<_$AppDatabase, $SchoolYearsTable> {
  $$SchoolYearsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get startDate => $composableBuilder(
    column: $table.startDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get endDate => $composableBuilder(
    column: $table.endDate,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SchoolYearsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SchoolYearsTable> {
  $$SchoolYearsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get accountId =>
      $composableBuilder(column: $table.accountId, builder: (column) => column);

  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get startDate =>
      $composableBuilder(column: $table.startDate, builder: (column) => column);

  GeneratedColumn<String> get endDate =>
      $composableBuilder(column: $table.endDate, builder: (column) => column);
}

class $$SchoolYearsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SchoolYearsTable,
          SchoolYearRow,
          $$SchoolYearsTableFilterComposer,
          $$SchoolYearsTableOrderingComposer,
          $$SchoolYearsTableAnnotationComposer,
          $$SchoolYearsTableCreateCompanionBuilder,
          $$SchoolYearsTableUpdateCompanionBuilder,
          (
            SchoolYearRow,
            BaseReferences<_$AppDatabase, $SchoolYearsTable, SchoolYearRow>,
          ),
          SchoolYearRow,
          PrefetchHooks Function()
        > {
  $$SchoolYearsTableTableManager(_$AppDatabase db, $SchoolYearsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SchoolYearsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SchoolYearsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SchoolYearsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> accountId = const Value.absent(),
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> startDate = const Value.absent(),
                Value<String> endDate = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SchoolYearsCompanion(
                accountId: accountId,
                id: id,
                name: name,
                startDate: startDate,
                endDate: endDate,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String accountId,
                required int id,
                required String name,
                required String startDate,
                required String endDate,
                Value<int> rowid = const Value.absent(),
              }) => SchoolYearsCompanion.insert(
                accountId: accountId,
                id: id,
                name: name,
                startDate: startDate,
                endDate: endDate,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SchoolYearsTable, SchoolYearRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $SchoolYearsTable,
                    SchoolYearRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SchoolYearsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SchoolYearsTable,
      SchoolYearRow,
      $$SchoolYearsTableFilterComposer,
      $$SchoolYearsTableOrderingComposer,
      $$SchoolYearsTableAnnotationComposer,
      $$SchoolYearsTableCreateCompanionBuilder,
      $$SchoolYearsTableUpdateCompanionBuilder,
      (
        SchoolYearRow,
        BaseReferences<_$AppDatabase, $SchoolYearsTable, SchoolYearRow>,
      ),
      SchoolYearRow,
      PrefetchHooks Function()
    >;
typedef $$TimeGridsTableCreateCompanionBuilder = TimeGridsCompanion Function({
  required String accountId,
  required String json,
  Value<int> rowid,
});
typedef $$TimeGridsTableUpdateCompanionBuilder = TimeGridsCompanion Function({
  Value<String> accountId,
  Value<String> json,
  Value<int> rowid,
});

class $$TimeGridsTableFilterComposer
    extends Composer<_$AppDatabase, $TimeGridsTable> {
  $$TimeGridsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get json => $composableBuilder(
    column: $table.json,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TimeGridsTableOrderingComposer
    extends Composer<_$AppDatabase, $TimeGridsTable> {
  $$TimeGridsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get json => $composableBuilder(
    column: $table.json,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TimeGridsTableAnnotationComposer
    extends Composer<_$AppDatabase, $TimeGridsTable> {
  $$TimeGridsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get accountId =>
      $composableBuilder(column: $table.accountId, builder: (column) => column);

  GeneratedColumn<String> get json =>
      $composableBuilder(column: $table.json, builder: (column) => column);
}

class $$TimeGridsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TimeGridsTable,
          TimeGridRow,
          $$TimeGridsTableFilterComposer,
          $$TimeGridsTableOrderingComposer,
          $$TimeGridsTableAnnotationComposer,
          $$TimeGridsTableCreateCompanionBuilder,
          $$TimeGridsTableUpdateCompanionBuilder,
          (
            TimeGridRow,
            BaseReferences<_$AppDatabase, $TimeGridsTable, TimeGridRow>,
          ),
          TimeGridRow,
          PrefetchHooks Function()
        > {
  $$TimeGridsTableTableManager(_$AppDatabase db, $TimeGridsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TimeGridsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TimeGridsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TimeGridsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> accountId = const Value.absent(),
                Value<String> json = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TimeGridsCompanion(
                accountId: accountId,
                json: json,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String accountId,
                required String json,
                Value<int> rowid = const Value.absent(),
              }) => TimeGridsCompanion.insert(
                accountId: accountId,
                json: json,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$TimeGridsTable, TimeGridRow>(table),
                  BaseReferences<_$AppDatabase, $TimeGridsTable, TimeGridRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TimeGridsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TimeGridsTable,
      TimeGridRow,
      $$TimeGridsTableFilterComposer,
      $$TimeGridsTableOrderingComposer,
      $$TimeGridsTableAnnotationComposer,
      $$TimeGridsTableCreateCompanionBuilder,
      $$TimeGridsTableUpdateCompanionBuilder,
      (
        TimeGridRow,
        BaseReferences<_$AppDatabase, $TimeGridsTable, TimeGridRow>,
      ),
      TimeGridRow,
      PrefetchHooks Function()
    >;
typedef $$CachedWeeksTableCreateCompanionBuilder =
    CachedWeeksCompanion Function({
      required String accountId,
      required String targetType,
      required int targetId,
      required String weekStart,
      required String periodsJson,
      required int fetchedAt,
      Value<int> rowid,
    });
typedef $$CachedWeeksTableUpdateCompanionBuilder =
    CachedWeeksCompanion Function({
      Value<String> accountId,
      Value<String> targetType,
      Value<int> targetId,
      Value<String> weekStart,
      Value<String> periodsJson,
      Value<int> fetchedAt,
      Value<int> rowid,
    });

class $$CachedWeeksTableFilterComposer
    extends Composer<_$AppDatabase, $CachedWeeksTable> {
  $$CachedWeeksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get targetType => $composableBuilder(
    column: $table.targetType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get targetId => $composableBuilder(
    column: $table.targetId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get weekStart => $composableBuilder(
    column: $table.weekStart,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get periodsJson => $composableBuilder(
    column: $table.periodsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedWeeksTableOrderingComposer
    extends Composer<_$AppDatabase, $CachedWeeksTable> {
  $$CachedWeeksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get targetType => $composableBuilder(
    column: $table.targetType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get targetId => $composableBuilder(
    column: $table.targetId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get weekStart => $composableBuilder(
    column: $table.weekStart,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get periodsJson => $composableBuilder(
    column: $table.periodsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedWeeksTableAnnotationComposer
    extends Composer<_$AppDatabase, $CachedWeeksTable> {
  $$CachedWeeksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get accountId =>
      $composableBuilder(column: $table.accountId, builder: (column) => column);

  GeneratedColumn<String> get targetType => $composableBuilder(
    column: $table.targetType,
    builder: (column) => column,
  );

  GeneratedColumn<int> get targetId =>
      $composableBuilder(column: $table.targetId, builder: (column) => column);

  GeneratedColumn<String> get weekStart =>
      $composableBuilder(column: $table.weekStart, builder: (column) => column);

  GeneratedColumn<String> get periodsJson => $composableBuilder(
    column: $table.periodsJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get fetchedAt =>
      $composableBuilder(column: $table.fetchedAt, builder: (column) => column);
}

class $$CachedWeeksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CachedWeeksTable,
          CachedWeekRow,
          $$CachedWeeksTableFilterComposer,
          $$CachedWeeksTableOrderingComposer,
          $$CachedWeeksTableAnnotationComposer,
          $$CachedWeeksTableCreateCompanionBuilder,
          $$CachedWeeksTableUpdateCompanionBuilder,
          (
            CachedWeekRow,
            BaseReferences<_$AppDatabase, $CachedWeeksTable, CachedWeekRow>,
          ),
          CachedWeekRow,
          PrefetchHooks Function()
        > {
  $$CachedWeeksTableTableManager(_$AppDatabase db, $CachedWeeksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedWeeksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedWeeksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedWeeksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> accountId = const Value.absent(),
                Value<String> targetType = const Value.absent(),
                Value<int> targetId = const Value.absent(),
                Value<String> weekStart = const Value.absent(),
                Value<String> periodsJson = const Value.absent(),
                Value<int> fetchedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedWeeksCompanion(
                accountId: accountId,
                targetType: targetType,
                targetId: targetId,
                weekStart: weekStart,
                periodsJson: periodsJson,
                fetchedAt: fetchedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String accountId,
                required String targetType,
                required int targetId,
                required String weekStart,
                required String periodsJson,
                required int fetchedAt,
                Value<int> rowid = const Value.absent(),
              }) => CachedWeeksCompanion.insert(
                accountId: accountId,
                targetType: targetType,
                targetId: targetId,
                weekStart: weekStart,
                periodsJson: periodsJson,
                fetchedAt: fetchedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CachedWeeksTable, CachedWeekRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $CachedWeeksTable,
                    CachedWeekRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedWeeksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CachedWeeksTable,
      CachedWeekRow,
      $$CachedWeeksTableFilterComposer,
      $$CachedWeeksTableOrderingComposer,
      $$CachedWeeksTableAnnotationComposer,
      $$CachedWeeksTableCreateCompanionBuilder,
      $$CachedWeeksTableUpdateCompanionBuilder,
      (
        CachedWeekRow,
        BaseReferences<_$AppDatabase, $CachedWeeksTable, CachedWeekRow>,
      ),
      CachedWeekRow,
      PrefetchHooks Function()
    >;
typedef $$AppStateTableCreateCompanionBuilder = AppStateCompanion Function({
  required String key,
  Value<String?> value,
  Value<int> rowid,
});
typedef $$AppStateTableUpdateCompanionBuilder = AppStateCompanion Function({
  Value<String> key,
  Value<String?> value,
  Value<int> rowid,
});

class $$AppStateTableFilterComposer
    extends Composer<_$AppDatabase, $AppStateTable> {
  $$AppStateTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AppStateTableOrderingComposer
    extends Composer<_$AppDatabase, $AppStateTable> {
  $$AppStateTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AppStateTableAnnotationComposer
    extends Composer<_$AppDatabase, $AppStateTable> {
  $$AppStateTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$AppStateTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AppStateTable,
          AppStateRow,
          $$AppStateTableFilterComposer,
          $$AppStateTableOrderingComposer,
          $$AppStateTableAnnotationComposer,
          $$AppStateTableCreateCompanionBuilder,
          $$AppStateTableUpdateCompanionBuilder,
          (
            AppStateRow,
            BaseReferences<_$AppDatabase, $AppStateTable, AppStateRow>,
          ),
          AppStateRow,
          PrefetchHooks Function()
        > {
  $$AppStateTableTableManager(_$AppDatabase db, $AppStateTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AppStateTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AppStateTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AppStateTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> key = const Value.absent(),
            Value<String?> value = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) => AppStateCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback: ({
            required String key,
            Value<String?> value = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) => AppStateCompanion.insert(key: key, value: value, rowid: rowid),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$AppStateTable, AppStateRow>(table),
                  BaseReferences<_$AppDatabase, $AppStateTable, AppStateRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AppStateTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AppStateTable,
      AppStateRow,
      $$AppStateTableFilterComposer,
      $$AppStateTableOrderingComposer,
      $$AppStateTableAnnotationComposer,
      $$AppStateTableCreateCompanionBuilder,
      $$AppStateTableUpdateCompanionBuilder,
      (AppStateRow, BaseReferences<_$AppDatabase, $AppStateTable, AppStateRow>),
      AppStateRow,
      PrefetchHooks Function()
    >;
typedef $$InfoCacheTableCreateCompanionBuilder = InfoCacheCompanion Function({
  required String accountId,
  required String key,
  required String json,
  required int fetchedAt,
  Value<int> rowid,
});
typedef $$InfoCacheTableUpdateCompanionBuilder = InfoCacheCompanion Function({
  Value<String> accountId,
  Value<String> key,
  Value<String> json,
  Value<int> fetchedAt,
  Value<int> rowid,
});

class $$InfoCacheTableFilterComposer
    extends Composer<_$AppDatabase, $InfoCacheTable> {
  $$InfoCacheTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get json => $composableBuilder(
    column: $table.json,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$InfoCacheTableOrderingComposer
    extends Composer<_$AppDatabase, $InfoCacheTable> {
  $$InfoCacheTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get json => $composableBuilder(
    column: $table.json,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$InfoCacheTableAnnotationComposer
    extends Composer<_$AppDatabase, $InfoCacheTable> {
  $$InfoCacheTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get accountId =>
      $composableBuilder(column: $table.accountId, builder: (column) => column);

  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get json =>
      $composableBuilder(column: $table.json, builder: (column) => column);

  GeneratedColumn<int> get fetchedAt =>
      $composableBuilder(column: $table.fetchedAt, builder: (column) => column);
}

class $$InfoCacheTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $InfoCacheTable,
          InfoCacheRow,
          $$InfoCacheTableFilterComposer,
          $$InfoCacheTableOrderingComposer,
          $$InfoCacheTableAnnotationComposer,
          $$InfoCacheTableCreateCompanionBuilder,
          $$InfoCacheTableUpdateCompanionBuilder,
          (
            InfoCacheRow,
            BaseReferences<_$AppDatabase, $InfoCacheTable, InfoCacheRow>,
          ),
          InfoCacheRow,
          PrefetchHooks Function()
        > {
  $$InfoCacheTableTableManager(_$AppDatabase db, $InfoCacheTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$InfoCacheTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$InfoCacheTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$InfoCacheTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> accountId = const Value.absent(),
                Value<String> key = const Value.absent(),
                Value<String> json = const Value.absent(),
                Value<int> fetchedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => InfoCacheCompanion(
                accountId: accountId,
                key: key,
                json: json,
                fetchedAt: fetchedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String accountId,
                required String key,
                required String json,
                required int fetchedAt,
                Value<int> rowid = const Value.absent(),
              }) => InfoCacheCompanion.insert(
                accountId: accountId,
                key: key,
                json: json,
                fetchedAt: fetchedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$InfoCacheTable, InfoCacheRow>(table),
                  BaseReferences<_$AppDatabase, $InfoCacheTable, InfoCacheRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$InfoCacheTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $InfoCacheTable,
      InfoCacheRow,
      $$InfoCacheTableFilterComposer,
      $$InfoCacheTableOrderingComposer,
      $$InfoCacheTableAnnotationComposer,
      $$InfoCacheTableCreateCompanionBuilder,
      $$InfoCacheTableUpdateCompanionBuilder,
      (
        InfoCacheRow,
        BaseReferences<_$AppDatabase, $InfoCacheTable, InfoCacheRow>,
      ),
      InfoCacheRow,
      PrefetchHooks Function()
    >;
typedef $$AbsenceLookupEntriesTableCreateCompanionBuilder =
    AbsenceLookupEntriesCompanion Function({
      required String accountId,
      required String kind,
      required int id,
      required String name,
      Value<int> rowid,
    });
typedef $$AbsenceLookupEntriesTableUpdateCompanionBuilder =
    AbsenceLookupEntriesCompanion Function({
      Value<String> accountId,
      Value<String> kind,
      Value<int> id,
      Value<String> name,
      Value<int> rowid,
    });

class $$AbsenceLookupEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $AbsenceLookupEntriesTable> {
  $$AbsenceLookupEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AbsenceLookupEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $AbsenceLookupEntriesTable> {
  $$AbsenceLookupEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AbsenceLookupEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $AbsenceLookupEntriesTable> {
  $$AbsenceLookupEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get accountId =>
      $composableBuilder(column: $table.accountId, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);
}

class $$AbsenceLookupEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AbsenceLookupEntriesTable,
          AbsenceLookupRow,
          $$AbsenceLookupEntriesTableFilterComposer,
          $$AbsenceLookupEntriesTableOrderingComposer,
          $$AbsenceLookupEntriesTableAnnotationComposer,
          $$AbsenceLookupEntriesTableCreateCompanionBuilder,
          $$AbsenceLookupEntriesTableUpdateCompanionBuilder,
          (
            AbsenceLookupRow,
            BaseReferences<
              _$AppDatabase,
              $AbsenceLookupEntriesTable,
              AbsenceLookupRow
            >,
          ),
          AbsenceLookupRow,
          PrefetchHooks Function()
        > {
  $$AbsenceLookupEntriesTableTableManager(
    _$AppDatabase db,
    $AbsenceLookupEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AbsenceLookupEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AbsenceLookupEntriesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$AbsenceLookupEntriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> accountId = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AbsenceLookupEntriesCompanion(
                accountId: accountId,
                kind: kind,
                id: id,
                name: name,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String accountId,
                required String kind,
                required int id,
                required String name,
                Value<int> rowid = const Value.absent(),
              }) => AbsenceLookupEntriesCompanion.insert(
                accountId: accountId,
                kind: kind,
                id: id,
                name: name,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$AbsenceLookupEntriesTable, AbsenceLookupRow>(
                    table,
                  ),
                  BaseReferences<
                    _$AppDatabase,
                    $AbsenceLookupEntriesTable,
                    AbsenceLookupRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AbsenceLookupEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AbsenceLookupEntriesTable,
      AbsenceLookupRow,
      $$AbsenceLookupEntriesTableFilterComposer,
      $$AbsenceLookupEntriesTableOrderingComposer,
      $$AbsenceLookupEntriesTableAnnotationComposer,
      $$AbsenceLookupEntriesTableCreateCompanionBuilder,
      $$AbsenceLookupEntriesTableUpdateCompanionBuilder,
      (
        AbsenceLookupRow,
        BaseReferences<
          _$AppDatabase,
          $AbsenceLookupEntriesTable,
          AbsenceLookupRow
        >,
      ),
      AbsenceLookupRow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$AccountsTableTableManager get accounts =>
      $$AccountsTableTableManager(_db, _db.accounts);
  $$MasterElementsTableTableManager get masterElements =>
      $$MasterElementsTableTableManager(_db, _db.masterElements);
  $$HolidaysTableTableManager get holidays =>
      $$HolidaysTableTableManager(_db, _db.holidays);
  $$SchoolYearsTableTableManager get schoolYears =>
      $$SchoolYearsTableTableManager(_db, _db.schoolYears);
  $$TimeGridsTableTableManager get timeGrids =>
      $$TimeGridsTableTableManager(_db, _db.timeGrids);
  $$CachedWeeksTableTableManager get cachedWeeks =>
      $$CachedWeeksTableTableManager(_db, _db.cachedWeeks);
  $$AppStateTableTableManager get appState =>
      $$AppStateTableTableManager(_db, _db.appState);
  $$InfoCacheTableTableManager get infoCache =>
      $$InfoCacheTableTableManager(_db, _db.infoCache);
  $$AbsenceLookupEntriesTableTableManager get absenceLookupEntries =>
      $$AbsenceLookupEntriesTableTableManager(_db, _db.absenceLookupEntries);
}
