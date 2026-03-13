import 'frb_loader_path_stub.dart'
    if (dart.library.io) 'frb_loader_path_io.dart'
    as impl;

String resolveFrbDefaultIoDirectory() => impl.resolveFrbDefaultIoDirectory();

String? resolveNativeProjectRootPath({String? currentDirectoryPath}) => impl
    .resolveNativeProjectRootPath(currentDirectoryPath: currentDirectoryPath);
