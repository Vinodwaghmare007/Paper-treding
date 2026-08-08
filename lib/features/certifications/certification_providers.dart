import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/certification_repository.dart';
import '../../domain/entities/certification.dart';
import '../auth/auth_providers.dart';

final certificationRepositoryProvider =
    Provider<CertificationRepository>((ref) => CertificationRepository());

final certificationsStreamProvider = StreamProvider<List<Certification>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return const Stream.empty();
  return ref.watch(certificationRepositoryProvider).watchCertifications(uid);
});
