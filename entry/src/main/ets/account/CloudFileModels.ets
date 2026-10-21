export class CloudFileSummary {
  configured: boolean = false;
  eligible: boolean = false;
  usedBytes: number = 0;
  quotaBytes: number = 1073741824;
  downloadBytes: number = 0;
  downloadQuotaBytes: number = 1073741824;
  chunkBytes: number = 1048576;
  cycleEndsAt: number | null = null;
}
export class CloudFileItem {
  id: string = '';
  name: string = '';
  kind: string = '';
  bytes: number = 0;
  state: string = '';
  manifestHash: string = '';
}
export class CloudFileList {
  files: CloudFileItem[] = [];
  nextCursor: string = '';
}
export class CloudChunk {
  index: number = 0;
  bytes: number = 0;
  sha256: string = '';
}
export class CloudManifest extends CloudFileItem {
  chunkBytes: number = 1048576;
  chunks: CloudChunk[] = [];
}
export class CloudTransferTicket extends CloudChunk {
  url: string = '';
  expiresAt: number = 0;
  md5: string = '';
  ready: boolean = false;
}
export class CloudUploadTask {
  manifestHash: string = '';
  reused: boolean = false;
  requestId: string = '';
  fileId: string = '';
  path: string = '';
  name: string = '';
  kind: string = '';
  bytes: number = 0;
}
