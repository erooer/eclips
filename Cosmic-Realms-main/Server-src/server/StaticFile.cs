using System.Collections.Specialized;
using Anna.Request;

namespace server
{
    class StaticFile : RequestHandler
    {
        private readonly string _contentType;
        private readonly byte[] _data;
        private readonly bool _preventCaching;

        public StaticFile(byte[] data, string contentType, bool preventCaching = false)
        {
            _contentType = contentType;
            _data = data;
            _preventCaching = preventCaching;
        }

        public override void HandleRequest(RequestContext context, NameValueCollection query)
        {
            var response = context.Response(_data);
            if (_preventCaching)
            {
                response.Headers["Cache-Control"] = "no-store, no-cache, must-revalidate, max-age=0";
                response.Headers["Pragma"] = "no-cache";
                response.Headers["Expires"] = "0";
            }
            Write(response, _contentType);
        }
    }
}
