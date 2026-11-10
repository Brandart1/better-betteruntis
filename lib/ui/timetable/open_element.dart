import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../core/models.dart';

/// Opens another element's timetable (teacher, class, room chip).
typedef OpenElementCallback = void Function(BuildContext context, TimetableTarget target);

/// Default: go_router route `/timetable/:type/:id` (type = [ElementType.apiName]).
void defaultOpenElement(BuildContext context, TimetableTarget t) =>
    context.push('/timetable/${t.type.apiName}/${t.id}');
