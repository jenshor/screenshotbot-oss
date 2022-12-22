package io.screenshotbot.plugin;

import com.android.build.gradle.api.TestVariant;
import org.gradle.api.DefaultTask;
import org.gradle.api.tasks.Input;
import org.gradle.api.tasks.TaskAction;
import com.android.build.gradle.api.*;
import com.android.build.gradle.*;
import org.gradle.api.*;

public class RecordFacebookTask extends DefaultTask {

    private TestedExtension androidExtension;
    public RecordFacebookTask() {
        setGroup("Screenshotbot Tasks");
    }

    public void init(TestVariant variant,
                     TestedExtension androidExtension,
                     ScreenshotbotPlugin.Extension extension) {
        dependsOn(variant.getConnectedInstrumentTestProvider());
        this.androidExtension = androidExtension;
    }

    @TaskAction
    public void record() {
        /*
          Might be useful in the future, but it gives null for the moment:
          androidExtension.getAdbOptions().getInstallOptions()
         */

        ScreenshotbotPlugin.println("hello world: " +
                                    androidExtension.getAdbExe().toString());
    }
}
