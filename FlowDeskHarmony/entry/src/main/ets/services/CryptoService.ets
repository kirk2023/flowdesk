import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { util } from '@kit.ArkTS';

const TAG = 'FlowDesk.Crypto';

class AesGcmParamsLocal {
  algName: string = 'GcmParamsSpec';
  iv: cryptoFramework.DataBlob = { data: new Uint8Array(0) };
  aad: cryptoFramework.DataBlob = { data: new Uint8Array(0) };
  authTag: cryptoFramework.DataBlob = { data: new Uint8Array(0) };
}

/**
 * CryptoService（MVP 简化版）
 * MVP 范围：ECDH P-256 密钥交换 + AES-256-GCM 加解密
 */
export class CryptoService {
  /**
   * 生成 ECDH P-256 临时密钥对
   */
  static async generateEcdhKeyPair(): Promise<EcdhKeyPair> {
    try {
      const generator = cryptoFramework.createAsyKeyGenerator('ECC256');
      const keyPair = await generator.generateKeyPair();
      const pubBlob = await keyPair.pubKey.getEncoded();
      const b64: string = CryptoService.bufToBase64(pubBlob.data);
      hilog.info(0x0001, TAG, 'ECDH key pair generated, pub len=%{public}d', pubBlob.data.length);
      return {
        privateKey: keyPair.priKey,
        publicKeyBase64: b64
      };
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(0x0001, TAG, 'generate key failed: %{public}s', e.message);
      throw new Error('Key gen failed: ' + e.message);
    }
  }

  /**
   * 派生共享密钥（取前 32 字节作为 AES key）
   */
  static async deriveSharedKey(
    localPrivateKey: cryptoFramework.PriKey,
    remotePublicKeyBase64: string
  ): Promise<Uint8Array> {
    try {
      const remotePubBytes: Uint8Array = CryptoService.base64ToBuf(remotePublicKeyBase64);
      const peerKey: cryptoFramework.PubKey = await CryptoService.importPublicKey(remotePubBytes);
      const keyAgreement = cryptoFramework.createKeyAgreement('ECC256');
      const sharedSecret = await keyAgreement.generateSecret(localPrivateKey, peerKey);
      hilog.info(0x0001, TAG, 'shared secret derived, len=%{public}d', sharedSecret.data.length);
      return sharedSecret.data.slice(0, 32);
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(0x0001, TAG, 'derive key failed: %{public}s', e.message);
      throw new Error('Derive failed: ' + e.message);
    }
  }

  private static async importPublicKey(pubBytes: Uint8Array): Promise<cryptoFramework.PubKey> {
    const generator = cryptoFramework.createAsyKeyGenerator('ECC256');
    const pubBlob: cryptoFramework.DataBlob = { data: pubBytes };
    const emptyBlob: cryptoFramework.DataBlob = { data: new Uint8Array(0) };
    const keyPair: cryptoFramework.KeyPair = await generator.convertKey(pubBlob, emptyBlob);
    return keyPair.pubKey;
  }

  /**
   * AES-256-GCM 加密
   * 输出格式：nonce(12) || ciphertext || authTag(16)
   */
  static async aesGcmEncrypt(
    key: Uint8Array,
    nonce: Uint8Array,
    plaintext: Uint8Array
  ): Promise<Uint8Array> {
    try {
      const cipher = cryptoFramework.createCipher('AES256|GCM|PKCS7');
      const symKeyGenerator = cryptoFramework.createSymKeyGenerator('AES256');
      const symKey = await symKeyGenerator.convertKey({ data: key });
      const params: AesGcmParamsLocal = new AesGcmParamsLocal();
      params.iv = { data: nonce };
      params.aad = { data: new Uint8Array(0) };
      params.authTag = { data: new Uint8Array(16) };
      await cipher.init(cryptoFramework.CryptoMode.ENCRYPT_MODE, symKey, params as cryptoFramework.ParamsSpec);
      const updateOut = await cipher.update({ data: plaintext });
      const tagOut = await cipher.doFinal(null);
      const cipherText: Uint8Array = updateOut.data;
      const authTag: Uint8Array = tagOut ? tagOut.data : new Uint8Array(16);
      const out: Uint8Array = new Uint8Array(12 + cipherText.length + 16);
      out.set(nonce, 0);
      out.set(cipherText, 12);
      out.set(authTag, 12 + cipherText.length);
      return out;
    } catch (err) {
      const e = err as BusinessError;
      const code: number = (e && typeof e.code === 'number') ? e.code : -1;
      const msg: string = (e && typeof e.message === 'string') ? e.message : String(err);
      hilog.error(0x0001, TAG, 'encrypt failed: code=%{public}d msg=%{public}s', code, msg);
      throw new Error('Encrypt failed[' + code + ']: ' + msg);
    }
  }

  /**
   * AES-256-GCM 解密
   * 输入格式：nonce(12) || ciphertext || authTag(16)
   */
  static async aesGcmDecrypt(
    key: Uint8Array,
    fullPayload: Uint8Array
  ): Promise<Uint8Array> {
    try {
      if (fullPayload.length < 28) {
        throw new Error('payload too short');
      }
      const nonce: Uint8Array = new Uint8Array(fullPayload.buffer, fullPayload.byteOffset, 12);
      const authTag: Uint8Array = new Uint8Array(
        fullPayload.buffer,
        fullPayload.byteOffset + fullPayload.length - 16,
        16
      );
      const ciphertext: Uint8Array = new Uint8Array(
        fullPayload.buffer,
        fullPayload.byteOffset + 12,
        fullPayload.length - 28
      );

      const cipher = cryptoFramework.createCipher('AES256|GCM|PKCS7');
      const symKeyGenerator = cryptoFramework.createSymKeyGenerator('AES256');
      const symKey = await symKeyGenerator.convertKey({ data: key });
      const params: AesGcmParamsLocal = new AesGcmParamsLocal();
      params.iv = { data: nonce };
      params.aad = { data: new Uint8Array(0) };
      params.authTag = { data: authTag };
      await cipher.init(cryptoFramework.CryptoMode.DECRYPT_MODE, symKey, params as cryptoFramework.ParamsSpec);
      const updateOut = await cipher.update({ data: ciphertext });
      await cipher.doFinal(null);
      return updateOut.data;
    } catch (err) {
      const e = err as BusinessError;
      const code: number = (e && typeof e.code === 'number') ? e.code : -1;
      const msg: string = (e && typeof e.message === 'string') ? e.message : String(err);
      hilog.error(0x0001, TAG, 'decrypt failed: code=%{public}d msg=%{public}s', code, msg);
      throw new Error('Decrypt failed[' + code + ']: ' + msg);
    }
  }

  static incrementNonce(nonce: Uint8Array): void {
    for (let i = nonce.length - 1; i >= 0; i--) {
      if (++nonce[i] !== 0) break;
    }
  }

  static bufToBase64(buf: Uint8Array): string {
    const helper = new util.Base64Helper();
    return helper.encodeToStringSync(buf);
  }

  static base64ToBuf(b64: string): Uint8Array {
    const helper = new util.Base64Helper();
    return helper.decodeSync(b64);
  }
}

export interface EcdhKeyPair {
  privateKey: cryptoFramework.PriKey;
  publicKeyBase64: string;
}
