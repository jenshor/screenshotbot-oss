

function updateAjaxResults($target) {
    $.ajax({
        url: $target.data("update"),
        data: $target.data("args"),
        success: function (result) {
            $target.html(result);
            callLiveOnAttach($target);
        },
        error: function () {
            alert("Something went wrong");
        },
    });
}

setupLiveOnAttach(".search", function () {
    $(this).on("input", function () {
        var val = $(this).val();
        var $target = $($(this).data("target"));

        var params = $target.data("args");

        params["search"] = val;
        var timeout = $target.data("timeout");
        if (timeout) {
            clearTimeout(timeout);
        }

        $target.data("timeout", setTimeout(function () {
            updateAjaxResults($target);
        }, 250));
    });
});


setupLiveOnAttach("ul.report-selector > li > a", function () {
    var currentState = history.state;
    var type = $(this).data("type");

    function switchTab() {
        var $ul = $(this).closest("ul");
        $ul.find("a").removeClass("active");
        $(this).addClass("active");
        var $target = $($ul.data("target"));
        var args = $target.data("args");

        args["type"] = type;
        setUrlParameter("type", type);

        updateAjaxResults($target);
    }

    $(this).click(function (e) {
        switchTab.call(this);

        e.preventDefault();
    });

});
