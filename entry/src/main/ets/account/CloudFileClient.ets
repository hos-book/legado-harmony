import { Context } from '@kit.AbilityKit';
import fs from '@ohos.file.fs';
import http from '@ohos.net.http';
import fileUri from '@ohos.file.fileuri';
import preferences from '@ohos.data.preferences';
import { util } from '@kit.ArkTS';
import cryptoFramework from '@ohos.security.cryptoFramework';
import { AccountCommerceApi } from './AccountCommerceApi';
import { AccountApiError } from './AccountCommerceModels';
import { AccountSessionStore } from './AccountSessionStore';
import { CloudTransferTicket, CloudFileItem, CloudFileList, CloudFileSummary, CloudManifest, CloudUploadTask } from './CloudFileModels';

export class CloudFileClient {
  private static paused: boolean = false;
  private static transferring: boolean = false;
  static pause(): void { CloudFileClient.paused = true; }
  static async summary(): Promise<CloudFileSummary> {
    return JSON.parse(await AccountCommerceApi.cloudRequest('/summary', 'GET', '', AccountSessionStore.token())) as CloudFileSummary;
  }
  static async list(after: string = ''): Promise<CloudFileList> {
    return JSON.parse(await AccountCommerceApi.cloudRequest(`?after=${encodeURIComponent(after)}`, 'GET', '', AccountSessionStore.token())) as CloudFileList;
  }
  static async remove(id: string): Promise<void> {
    await AccountCommerceApi.cloudRequest(`/${id}/delete`, 'POST', '{}', AccountSessionStore.token());
  }
  static async pending(context: Context): Promise<CloudUploadTask | null> {
    const store = await preferences.getPreferences(context, 'cloud_file_transfers');
    const raw = await store.get(`upload_${AccountSessionStore.account().userId}`, '') as string;
    return raw ? JSON.parse(raw) as CloudUploadTask : null;
  }
  static async stage(context: Context, uri: string, name: string, kind: string): Promise<void> {
    if (await CloudFileClient.pending(context)) throw new Error('请先继续或取消上次上传');
    const userId = AccountSessionStore.account().userId;
    if (!userId) throw new Error('请先登录');
    const task = new CloudUploadTask();
    task.requestId = util.generateRandomUUID(); task.name = name; task.kind = kind;
    const dir = `${context.filesDir}/cloud_transfers`;
    if (!fs.accessSync(dir)) await fs.mkdir(dir);
    task.path = `${dir}/${task.requestId}.upload`;
    const original = await fs.stat(uri);
    if (original.size < 1 || original.size > 1073741824) throw new Error('文件大小须为 1 字节至 1GB');
    await fs.copy(uri.startsWith('/') ? fileUri.getUriFromPath(uri) : uri, fileUri.getUriFromPath(task.path));
    task.bytes = (await fs.stat(task.path)).size;
    if (task.bytes < 1 || task.bytes > 1073741824) {
      await fs.unlink(task.path); throw new Error('文件大小须为 1 字节至 1GB');
    }
    const store = await preferences.getPreferences(context, 'cloud_file_transfers');
    await store.put(`upload_${userId}`, JSON.stringify(task)); await store.flush();
  }
  static async cancelUpload(context: Context): Promise<void> {
    if (CloudFileClient.transferring) throw new Error('请先暂停传输');
    const task = await CloudFileClient.pending(context);
    if (!task) return;
    if (task.fileId && !task.reused) await CloudFileClient.remove(task.fileId);
    const store = await preferences.getPreferences(context, 'cloud_file_transfers');
    await store.delete(`upload_${AccountSessionStore.account().userId}`); await store.flush();
    if (fs.accessSync(task.path)) await fs.unlink(task.path);
  }
  static async upload(context: Context, progress: (done: number, total: number) => void): Promise<string> {
    if (CloudFileClient.transferring) throw new Error('已有文件正在传输');
    CloudFileClient.transferring = true; CloudFileClient.paused = false;
    const userId = AccountSessionStore.account().userId, token = AccountSessionStore.token();
    try {
      const task = await CloudFileClient.pending(context);
      if (!task) throw new Error('没有待上传文件');
      const store = await preferences.getPreferences(context, 'cloud_file_transfers');
      if (!task.manifestHash) {
        const hashes: string[] = [];
        const source = await fs.open(task.path, fs.OpenMode.READ_ONLY);
        try {
          for (let offset = 0, index = 0; offset < task.bytes; index++) {
            CloudFileClient.check(userId);
            const length = Math.min(1048576, task.bytes - offset);
            hashes.push(`${index}:${length}:${CloudFileClient.sha256(await CloudFileClient.read(source.fd, offset, length))}`);
            offset += length;
          }
        } finally { await fs.close(source); }
        task.manifestHash = CloudFileClient.sha256(new util.TextEncoder().encodeInto(hashes.join('\n')));
        await store.put(`upload_${userId}`, JSON.stringify(task)); await store.flush();
      }
      const prepared = JSON.parse(await AccountCommerceApi.cloudRequest('/prepare', 'POST', JSON.stringify({
        requestId: task.requestId, name: task.name, kind: task.kind, bytes: task.bytes, manifestHash: task.manifestHash
      }), token)) as CloudFileItem;
      task.fileId = prepared.id;
      task.reused = prepared.state === 'READY';
      await store.put(`upload_${userId}`, JSON.stringify(task)); await store.flush();
      const manifest = JSON.parse(await AccountCommerceApi.cloudRequest(`/${task.fileId}`, 'GET', '', token)) as CloudManifest;
      const file = await fs.open(task.path, fs.OpenMode.READ_ONLY);
      try {
        for (let offset = 0, index = 0; offset < task.bytes; index++) {
          CloudFileClient.check(userId);
          const length = Math.min(manifest.chunkBytes, task.bytes - offset);
          const bytes = await CloudFileClient.read(file.fd, offset, length);
          const hash = CloudFileClient.sha256(bytes);
          const old = manifest.chunks.find(chunk => chunk.index === index);
          if (old && old.sha256 !== hash) throw new Error('本地文件已改变，请取消任务后重新上传');
          if (!old) {
            const md = cryptoFramework.createMd('MD5'); md.updateSync({ data: bytes });
            const md5 = new util.Base64Helper().encodeToStringSync(md.digestSync().data);
            const ticket = JSON.parse(await CloudFileClient.ticketRequest(`/${task.fileId}/upload-ticket`,
              JSON.stringify({ index: index, bytes: length, sha256: hash, md5: md5 }), token, userId)) as CloudTransferTicket;
            if (ticket.bytes !== length || ticket.sha256 !== hash) throw new Error('上传授权校验失败');
            if (!ticket.ready) {
              if (ticket.md5 !== md5) throw new Error('上传授权校验失败');
              await CloudFileClient.directRequest(ticket, bytes, userId);
            }
            CloudFileClient.check(userId);
            const response = JSON.parse(await AccountCommerceApi.cloudRequest(`/${task.fileId}/chunks/${index}/confirm`,
              'POST', '{}', token)) as CloudTransferTicket;
            if (response.sha256 !== hash) throw new Error('上传校验失败，请重试');
          }
          offset += length; progress(offset, task.bytes);
        }
      } finally { await fs.close(file); }
      CloudFileClient.check(userId);
      await AccountCommerceApi.cloudRequest(`/${task.fileId}/complete`, 'POST', '{}', token);
      await store.delete(`upload_${userId}`); await store.flush();
      await fs.unlink(task.path);
      return task.fileId;
    } finally { CloudFileClient.transferring = false; }
  }
  static async download(context: Context, item: CloudFileItem,
    progress: (done: number, total: number) => void): Promise<string> {
    if (CloudFileClient.transferring) throw new Error('已有文件正在传输');
    CloudFileClient.transferring = true; CloudFileClient.paused = false;
    const userId = AccountSessionStore.account().userId, token = AccountSessionStore.token();
    try {
      const manifest = JSON.parse(await AccountCommerceApi.cloudRequest(`/${item.id}`, 'GET', '', token)) as CloudManifest;
      if (manifest.state !== 'READY' || manifest.chunkBytes !== 1048576 || manifest.bytes < 1 || manifest.bytes > 1073741824
        || manifest.chunks.length !== Math.ceil(manifest.bytes / manifest.chunkBytes)) throw new Error('云文件清单无效');
      const dir = `${context.filesDir}/cloud_transfers`;
      if (!fs.accessSync(dir)) await fs.mkdir(dir);
      const path = `${dir}/${userId}_${item.id}.download`;
      const file = await fs.open(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE);
      try {
        let offset = 0;
        for (let index = 0; index < manifest.chunks.length; index++) {
          CloudFileClient.check(userId);
          const chunk = manifest.chunks[index];
          const expected = Math.min(manifest.chunkBytes, manifest.bytes - offset);
          if (chunk.index !== index || chunk.bytes !== expected) throw new Error('云文件分块清单无效');
          const size = (await fs.stat(path)).size;
          let valid = false;
          if (size >= offset + chunk.bytes) valid = CloudFileClient.sha256(await CloudFileClient.read(file.fd, offset, chunk.bytes)) === chunk.sha256;
          if (!valid) {
            const ticket = JSON.parse(await CloudFileClient.ticketRequest(`/${item.id}/chunks/${index}/download-ticket`,
              JSON.stringify({ requestId: util.generateRandomUUID() }), token, userId)) as CloudTransferTicket;
            if (ticket.bytes !== chunk.bytes || ticket.sha256 !== chunk.sha256) throw new Error('下载授权校验失败');
            const data = await CloudFileClient.directRequest(ticket, null, userId);
            CloudFileClient.check(userId);
            if (data.length !== chunk.bytes || CloudFileClient.sha256(data) !== chunk.sha256) throw new Error('下载校验失败，请重试');
            let written = 0;
            while (written < data.length) {
              const piece = data.slice(written);
              const count = await fs.write(file.fd, piece.buffer, { offset: offset + written, length: piece.length });
              if (count <= 0) throw new Error('保存文件失败');
              written += count;
            }
          }
          offset += chunk.bytes; progress(offset, manifest.bytes);
        }
      } finally { await fs.close(file); }
      CloudFileClient.check(userId);
      return path;
    } finally { CloudFileClient.transferring = false; }
  }
  // Repeat an ambiguous API request with the same body/requestId, never a new charge identifier.
  private static async ticketRequest(path: string, body: string, token: string, userId: string): Promise<string> {
    for (let attempt = 0; attempt < 2; attempt++) {
      CloudFileClient.check(userId);
      try { return await AccountCommerceApi.cloudRequest(path, 'POST', body, token); }
      catch (error) {
        if (attempt === 1 || (error instanceof AccountApiError && error.statusCode > 0 && error.statusCode < 500)) {
          throw error as Error;
        }
      }
    }
    throw new Error('获取传输授权失败');
  }
  private static async directRequest(ticket: CloudTransferTicket, body: Uint8Array | null, userId: string): Promise<Uint8Array> {
    if (!ticket.url.startsWith('https://') || ticket.bytes < 1 || ticket.bytes > 1048576) throw new Error('云文件授权无效');
    for (let attempt = 0; attempt < 2; attempt++) {
      CloudFileClient.check(userId);
      const request = http.createHttp();
      let response: http.HttpResponse | null = null;
      try {
        // Separate HTTP client: account Bearer credentials must never be sent to OBS.
        const headers: Record<string, string> = { 'Cache-Control': 'no-store' };
        if (body !== null) {
          headers['Content-Type'] = 'application/octet-stream';
          headers['Content-MD5'] = ticket.md5;
        }
        response = await request.request(ticket.url, {
          method: body === null ? http.RequestMethod.GET : http.RequestMethod.PUT,
          header: headers, extraData: body === null ? undefined : body.buffer,
          connectTimeout: 10000, readTimeout: 20000, usingCache: false,
          maxLimit: 2097152, expectDataType: http.HttpDataType.ARRAY_BUFFER
        });
      } catch (_) {
        // Network failure: reuse this short-lived capability once; no extra API quota charge.
        continue;
      } finally { request.destroy(); }
      if (!response) continue;
      // An HTTP answer is final for this capability, so report it instead of a generic network error.
      if (response.responseCode === 403) throw new Error('云文件授权已过期，请稍后继续传输');
      if (response.responseCode < 200 || response.responseCode >= 300) {
        throw new Error(`云文件传输失败（${response.responseCode}），可稍后继续`);
      }
      return body === null ? new Uint8Array(response.result as ArrayBuffer) : new Uint8Array(0);
    }
    throw new Error('云文件直连失败，请检查网络后继续传输');
  }
  private static check(userId: string): void {
    if (CloudFileClient.paused) throw new Error('传输已暂停，可稍后继续');
    if (!userId || AccountSessionStore.account().userId !== userId || !AccountSessionStore.isLoggedIn()) throw new Error('账号已改变，传输已停止');
  }
  private static async read(fd: number, offset: number, length: number): Promise<Uint8Array> {
    const data = new Uint8Array(length); let read = 0;
    while (read < length) {
      const buffer = new ArrayBuffer(length - read);
      const count = await fs.read(fd, buffer, { offset: offset + read, length: buffer.byteLength });
      if (count <= 0) throw new Error('本地文件不完整');
      data.set(new Uint8Array(buffer, 0, count), read); read += count;
    }
    return data;
  }
  private static sha256(bytes: Uint8Array): string {
    const md = cryptoFramework.createMd('SHA256'); md.updateSync({ data: bytes });
    let hash = ''; for (const byte of md.digestSync().data) hash += byte.toString(16).padStart(2, '0');
    return hash;
  }
}
