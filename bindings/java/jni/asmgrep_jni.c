/*
 * JNI adapter for com.asmgrep.Asmgrep. It marshals arguments between the JVM
 * and libasmgrep and contains no search logic.
 */
#include <jni.h>

#include <stddef.h>
#include <stdint.h>

#include "asmgrep.h"

static void throw_status(JNIEnv *env, int status)
{
    jclass cls = (*env)->FindClass(env, "com/asmgrep/AsmgrepException");
    if (!cls)
        return;
    jmethodID ctor = (*env)->GetMethodID(env, cls, "<init>", "(ILjava/lang/String;)V");
    if (!ctor)
        return;
    jstring msg = (*env)->NewStringUTF(env, asmgrep_strerror(status));
    jobject ex = (*env)->NewObject(env, cls, ctor, (jint)status, msg);
    if (ex)
        (*env)->Throw(env, (jthrowable)ex);
}

JNIEXPORT jlong JNICALL
Java_com_asmgrep_Asmgrep_nativeSearchFile(JNIEnv *env, jclass cls, jbyteArray pattern,
                                          jbyteArray path, jint flags)
{
    (void)cls;
    jbyte *pat = (*env)->GetByteArrayElements(env, pattern, NULL);
    jbyte *file = (*env)->GetByteArrayElements(env, path, NULL);
    if (!pat || !file) {
        if (pat)
            (*env)->ReleaseByteArrayElements(env, pattern, pat, JNI_ABORT);
        if (file)
            (*env)->ReleaseByteArrayElements(env, path, file, JNI_ABORT);
        return 0;
    }
    asmgrep_result *result = NULL;
    int status = asmgrep_search_file((const char *)pat, (const char *)file,
                                     (unsigned)flags, &result);
    (*env)->ReleaseByteArrayElements(env, pattern, pat, JNI_ABORT);
    (*env)->ReleaseByteArrayElements(env, path, file, JNI_ABORT);
    if (status != 0) {
        throw_status(env, status);
        return 0;
    }
    return (jlong)(intptr_t)result;
}

JNIEXPORT jlong JNICALL
Java_com_asmgrep_Asmgrep_nativeSearchBuffer(JNIEnv *env, jclass cls, jbyteArray data,
                                            jbyteArray pattern, jint flags)
{
    (void)cls;
    jsize dlen = (*env)->GetArrayLength(env, data);
    jsize plen = (*env)->GetArrayLength(env, pattern);
    jbyte *buf = (*env)->GetByteArrayElements(env, data, NULL);
    jbyte *pat = (*env)->GetByteArrayElements(env, pattern, NULL);
    if (!buf || !pat) {
        if (buf)
            (*env)->ReleaseByteArrayElements(env, data, buf, JNI_ABORT);
        if (pat)
            (*env)->ReleaseByteArrayElements(env, pattern, pat, JNI_ABORT);
        return 0;
    }
    asmgrep_result *result = NULL;
    int status = asmgrep_search_buffer(buf, (size_t)dlen, (const char *)pat,
                                       (size_t)plen, (unsigned)flags, &result);
    (*env)->ReleaseByteArrayElements(env, data, buf, JNI_ABORT);
    (*env)->ReleaseByteArrayElements(env, pattern, pat, JNI_ABORT);
    if (status != 0) {
        throw_status(env, status);
        return 0;
    }
    return (jlong)(intptr_t)result;
}

JNIEXPORT jint JNICALL
Java_com_asmgrep_Asmgrep_nativeCount(JNIEnv *env, jclass cls, jlong handle)
{
    (void)env;
    (void)cls;
    return (jint)asmgrep_result_count((const asmgrep_result *)(intptr_t)handle);
}

JNIEXPORT jlong JNICALL
Java_com_asmgrep_Asmgrep_nativeLineNumber(JNIEnv *env, jclass cls, jlong handle, jint index)
{
    (void)env;
    (void)cls;
    return (jlong)asmgrep_result_line_number((const asmgrep_result *)(intptr_t)handle,
                                             (size_t)index);
}

JNIEXPORT jbyteArray JNICALL
Java_com_asmgrep_Asmgrep_nativeText(JNIEnv *env, jclass cls, jlong handle, jint index)
{
    (void)cls;
    const asmgrep_result *result = (const asmgrep_result *)(intptr_t)handle;
    size_t len = asmgrep_result_length(result, (size_t)index);
    jbyteArray out = (*env)->NewByteArray(env, (jsize)len);
    if (out && len)
        (*env)->SetByteArrayRegion(env, out, 0, (jsize)len,
                                   (const jbyte *)asmgrep_result_text(result, (size_t)index));
    return out;
}

JNIEXPORT void JNICALL
Java_com_asmgrep_Asmgrep_nativeFree(JNIEnv *env, jclass cls, jlong handle)
{
    (void)env;
    (void)cls;
    asmgrep_free((asmgrep_result *)(intptr_t)handle);
}

JNIEXPORT jstring JNICALL
Java_com_asmgrep_Asmgrep_nativeVersion(JNIEnv *env, jclass cls)
{
    (void)cls;
    return (*env)->NewStringUTF(env, asmgrep_version());
}
